import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure, SubjectOption;

/// Data layer for the Student Profile → Subjects tab.
///
/// Source of truth is Firestore, read through Riverpod providers; widgets
/// only `watch` state and dispatch to [StudentProfileSubjectsController].
/// No Firestore access from widgets.
///
/// Model (05 Database v1.8):
/// - Access (ON/OFF) lives in `subject_access_assignments/{studentId}_
///   {subjectId}` (`enabled`, soft-deleted via `is_deleted`). It is
///   independent from `subscriptions` and is evaluated first.
/// - Plan (FREE / PRO / MAX) is subject-scoped: the active, non-deleted
///   `subscriptions` document for this (student, subject) pair points at a
///   `plans` document whose `plan_key` (`public_free` / `center_free` /
///   `center_pro` / `center_max`) resolves the display label. There is no
///   global student plan on this screen.
///
/// Writes go exclusively through the audited Cloud Function callables
/// (`setSubjectAccess`, `activateFreePlan`, `upgrade`/`downgrade`), which
/// enforce `requireStudentAccessManager` (teacher or delegated
/// `admin_students`) server-side and write `admin_audit_log` / analytics
/// events. The client never invents permission or audit identifiers.

/// One non-deleted access assignment of a student.
class StudentSubjectAssignment {
  final String subjectId;
  final bool enabled;

  const StudentSubjectAssignment({
    required this.subjectId,
    required this.enabled,
  });

  factory StudentSubjectAssignment.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    return StudentSubjectAssignment(
      subjectId: (data['subject_id'] as String?) ?? doc.id,
      enabled: data['enabled'] == true,
    );
  }
}

/// One active, non-deleted subscription of a student for one subject.
class StudentSubjectSubscription {
  final String subjectId;
  final String planId;

  const StudentSubjectSubscription({
    required this.subjectId,
    required this.planId,
  });

  factory StudentSubjectSubscription.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    return StudentSubjectSubscription(
      subjectId: (data['subject_id'] as String?) ?? doc.id,
      planId: (data['plan_id'] as String?) ?? '',
    );
  }
}

/// One registered-subject row of the Subjects table: the student has a
/// non-deleted access assignment for [subjectId]; [planLabel] is the
/// subject-scoped plan (`FREE` / `PRO` / `MAX`) or empty when no active
/// subscription exists yet for the pair (rendered as `—`, never invented).
class StudentSubjectRegistration {
  final String subjectId;
  final String title;
  final String? gradeKey;
  final String planLabel;
  final bool enabled;

  const StudentSubjectRegistration({
    required this.subjectId,
    required this.title,
    required this.gradeKey,
    required this.planLabel,
    required this.enabled,
  });
}

/// Display label for a `plans` document id. Resolution is data-driven from
/// the canonical `plan_key` (`public_free` / `center_free` / `center_pro` /
/// `center_max`); unknown keys resolve to empty (rendered as `—`).
String planDisplayForKey(String? planKey) {
  final String key = (planKey ?? '').toLowerCase();
  if (key.endsWith('_max') || key == 'max') return 'MAX';
  if (key.endsWith('_pro') || key == 'pro') return 'PRO';
  if (key.endsWith('_free') ||
      key == 'free' ||
      key == 'guest' ||
      key.isEmpty) {
    return key.isEmpty ? '' : 'FREE';
  }
  return '';
}

/// Pure combine step (unit-testable): registered subjects are exactly the
/// non-deleted assignments joined with the subject catalog; the plan comes
/// from the active subscription of the same (student, subject) pair.
List<StudentSubjectRegistration> buildStudentSubjectRegistrations({
  required List<SubjectOption> subjects,
  required List<StudentSubjectAssignment> assignments,
  required List<StudentSubjectSubscription> subscriptions,
  required Map<String, String> planLabels,
}) {
  final Map<String, SubjectOption> byId = <String, SubjectOption>{
    for (final SubjectOption s in subjects) s.id: s,
  };
  final Map<String, String> planBySubject = <String, String>{
    for (final StudentSubjectSubscription s in subscriptions)
      s.subjectId: planLabels[s.planId] ?? '',
  };
  final List<StudentSubjectRegistration> rows = <StudentSubjectRegistration>[];
  for (final StudentSubjectAssignment a in assignments) {
    final SubjectOption? subject = byId[a.subjectId];
    // The platform Subject catalog stays authoritative for titles; an
    // assignment whose subject document is gone (deleted platform-side)
    // is skipped rather than rendered with invented data.
    if (subject == null) continue;
    rows.add(StudentSubjectRegistration(
      subjectId: a.subjectId,
      title: subject.title,
      gradeKey: subject.gradeKey,
      planLabel: planBySubject[a.subjectId] ?? '',
      enabled: a.enabled,
    ));
  }
  rows.sort((a, b) => a.title.compareTo(b.title));
  return rows;
}

/// Live non-deleted access assignments of one student.
///
/// Single-filter query only (`student_id`); the `is_deleted` filter is
/// applied client-side so no composite index is required.
final studentSubjectAssignmentsProvider =
    StreamProvider.family<List<StudentSubjectAssignment>, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('subject_access_assignments')
      .where('student_id', isEqualTo: studentId)
      .snapshots()
      .map((snap) => snap.docs
          .where((doc) => doc.data()['is_deleted'] != true)
          .map(StudentSubjectAssignment.fromDoc)
          .toList(growable: false));
});

/// Live active, non-deleted subscriptions of one student.
///
/// Single-filter query only (`student_id`); status / soft-delete filters
/// are applied client-side so no composite index is required.
final studentSubjectSubscriptionsProvider =
    StreamProvider.family<List<StudentSubjectSubscription>, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('subscriptions')
      .where('student_id', isEqualTo: studentId)
      .snapshots()
      .map((snap) => snap.docs
          .where((doc) =>
              doc.data()['status'] == 'active' &&
              doc.data()['is_deleted'] != true)
          .map(StudentSubjectSubscription.fromDoc)
          .toList(growable: false));
});

/// Live plan document id → display label (`FREE` / `PRO` / `MAX`).
final subjectPlanLabelsProvider =
    StreamProvider<Map<String, String>>((ref) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db.collection('plans').snapshots().map((snap) {
    return <String, String>{
      for (final doc in snap.docs)
        doc.id: planDisplayForKey(doc.data()['plan_key'] as String?),
    };
  });
});

/// Combined registered-subject rows for the Subjects table of [studentId].
///
/// Combines the four source streams (catalog, assignments, subscriptions,
/// plans) with one manual fan-in — the same pattern as
/// `tabLecturesProvider` — so the table re-emits whenever any source
/// changes and stays in `loading` until every source has produced.
final studentProfileSubjectsProvider =
    StreamProvider.family<List<StudentSubjectRegistration>, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  late final StreamController<List<StudentSubjectRegistration>> controller;
  List<SubjectOption> subjects = const <SubjectOption>[];
  List<StudentSubjectAssignment> assignments =
      const <StudentSubjectAssignment>[];
  List<StudentSubjectSubscription> subscriptions =
      const <StudentSubjectSubscription>[];
  Map<String, String> planLabels = const <String, String>{};
  int ready = 0;
  final List<StreamSubscription> subs = <StreamSubscription>[];

  void emit() {
    // Bits: 1 subjects, 2 assignments, 4 subscriptions, 8 plans.
    // Emit only once every source produced (15) — never a partial join.
    if (ready != 15 || controller.isClosed) return;
    controller.add(buildStudentSubjectRegistrations(
      subjects: subjects,
      assignments: assignments,
      subscriptions: subscriptions,
      planLabels: planLabels,
    ));
  }

  controller = StreamController<List<StudentSubjectRegistration>>(
    onListen: () {
      subs.addAll(<StreamSubscription>[
        db
            .collection('subjects')
            .where('is_deleted', isEqualTo: false)
            .orderBy('display_order')
            .snapshots()
            .listen(
          (snap) {
            subjects = snap.docs
                .map(SubjectOption.fromDoc)
                .toList(growable: false);
            ready |= 1;
            emit();
          },
          onError: controller.addError,
        ),
        db
            .collection('subject_access_assignments')
            .where('student_id', isEqualTo: studentId)
            .snapshots()
            .listen(
          (snap) {
            assignments = snap.docs
                .where((doc) => doc.data()['is_deleted'] != true)
                .map(StudentSubjectAssignment.fromDoc)
                .toList(growable: false);
            ready |= 2;
            emit();
          },
          onError: controller.addError,
        ),
        db
            .collection('subscriptions')
            .where('student_id', isEqualTo: studentId)
            .snapshots()
            .listen(
          (snap) {
            subscriptions = snap.docs
                .where((doc) =>
                    doc.data()['status'] == 'active' &&
                    doc.data()['is_deleted'] != true)
                .map(StudentSubjectSubscription.fromDoc)
                .toList(growable: false);
            ready |= 4;
            emit();
          },
          onError: controller.addError,
        ),
        db.collection('plans').snapshots().listen(
          (snap) {
            planLabels = <String, String>{
              for (final doc in snap.docs)
                doc.id:
                    planDisplayForKey(doc.data()['plan_key'] as String?),
            };
            ready |= 8;
            emit();
          },
          onError: controller.addError,
        ),
      ]);
    },
  );

  ref.onDispose(() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    await controller.close();
  });
  return controller.stream;
});

/// One subject picked in an add overlay, with its toggle + plan choice.
class NewStudentSubject {
  final String subjectId;
  final bool enabled;
  final String plan;

  const NewStudentSubject({
    required this.subjectId,
    required this.enabled,
    required this.plan,
  });
}

/// Pure pick step (unit-testable): builds the commit list from the FULL
/// in-scope subject list — the same list the overlay displayed — applying
/// persisted/explicit toggle states and the FREE plan default for rows
/// the user never touched.
///
/// Rationale: the subject overlays only record entries for rows the user
/// physically toggles/selects; untouched rows leave no entry in the
/// returned maps and therefore resolve to OFF (never default-ON), exactly
/// as displayed. Iterating only the returned maps would silently drop
/// those rows; iterating the scope commits every displayed row with the
/// state the reviewer saw. Already-registered subjects are excluded
/// (duplicate protection; the deterministic `{studentId}_{subjectId}`
/// assignment id plus `enforceOneSubscriptionPerSubject` stay
/// authoritative).
List<NewStudentSubject> buildNewStudentSubjects({
  required List<SubjectOption> scope,
  required Map<String, bool> toggles,
  required Map<String, String> plans,
  required Set<String> alreadyRegistered,
}) {
  final List<NewStudentSubject> picked = <NewStudentSubject>[];
  final Set<String> seen = <String>{};
  void add(String subjectId) {
    if (!seen.add(subjectId)) return;
    if (alreadyRegistered.contains(subjectId)) return;
    picked.add(NewStudentSubject(
      subjectId: subjectId,
      enabled: toggles[subjectId] ?? false,
      plan: plans[subjectId] ?? 'free',
    ));
  }

  for (final SubjectOption subject in scope) {
    add(subject.id);
  }
  // Defensive: entries for ids that left the scope while the overlay was
  // open are still honored instead of silently dropped.
  for (final String subjectId in toggles.keys) {
    add(subjectId);
  }
  for (final String subjectId in plans.keys) {
    add(subjectId);
  }
  return picked;
}

/// Subject mutations for the Student Profile → Subjects tab.
///
/// Every write goes through the existing audited callables — never direct
/// Firestore writes — so `requireStudentAccessManager` (teacher or
/// delegated `admin_students`), `admin_audit_log`, and analytics events
/// keep applying exactly as they do for the approval flow. Permission
/// failures surface as [DecisionFailure] with the backend message.
class StudentProfileSubjectsController {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

  const StudentProfileSubjectsController(this._functions, this._db);

  String _message(Object error) {
    if (error is FirebaseFunctionsException) {
      final String? message = error.message;
      if (message != null && message.trim().isNotEmpty) return message;
      return switch (error.code) {
        'permission-denied' => 'لا تملك صلاحية تنفيذ هذا الإجراء.',
        'failed-precondition' => 'تعذّر تنفيذ الإجراء: حالة البيانات تغيّرت.',
        'not-found' => 'تعذّر العثور على الطالب أو المادة.',
        'invalid-argument' => 'بيانات غير مكتملة.',
        _ => 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.',
      };
    }
    return 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';
  }

  /// Immediate ON/OFF access change for an already-registered subject.
  /// The assignment stays registered; only `enabled` flips.
  Future<void> setAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
  }) async {
    try {
      await _functions.httpsCallable('setSubjectAccess').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'enabled': enabled,
        },
      );
    } catch (e) {
      throw DecisionFailure(_message(e));
    }
  }

  /// Delete = soft-delete (archive) the student-subject assignment after
  /// the UI confirmation. The platform Subject document is untouched;
  /// other students are unaffected.
  ///
  /// Known backend gap (reported, not silently worked around): no approved
  /// callable cancels the subject-scoped `subscriptions` document, so the
  /// subscription row is left for the existing lifecycle paths while the
  /// assignment archive immediately revokes every access path (access
  /// evaluation requires a non-deleted, enabled assignment first).
  Future<void> removeSubject({
    required String studentId,
    required String subjectId,
    required bool enabled,
  }) async {
    try {
      await _functions.httpsCallable('setSubjectAccess').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'enabled': enabled,
          'isDeleted': true,
        },
      );
    } catch (e) {
      throw DecisionFailure(_message(e));
    }
  }

  /// Adds subjects picked in the add overlays. Already-registered
  /// (non-deleted) subjects are skipped — the deterministic
  /// `{studentId}_{subjectId}` assignment id plus
  /// `enforceOneSubscriptionPerSubject` remain authoritative against
  /// duplicates.
  ///
  /// Per subject: create/restore the assignment via `setSubjectAccess`
  /// (explicit `isDeleted: false` so a previously removed subject is
  /// restored, not left archived), then for enabled rows ensure the
  /// subject-scoped subscription — `activateFreePlan` for FREE, followed
  /// by `upgrade` to the matching active plan document for PRO/MAX.
  Future<void> addSubjects({
    required String studentId,
    required bool isCenter,
    required List<NewStudentSubject> subjects,
    required Set<String> alreadyRegistered,
  }) async {
    final String studentType =
        isCenter ? 'center_student' : 'guest';
    for (final NewStudentSubject item in subjects) {
      if (alreadyRegistered.contains(item.subjectId)) continue;
      try {
        await _functions.httpsCallable('setSubjectAccess').call(
          <String, Object>{
            'studentId': studentId,
            'subjectId': item.subjectId,
            'enabled': item.enabled,
            'isDeleted': false,
          },
        );
        if (!item.enabled) continue;
        await _applyPlan(
          studentId: studentId,
          studentType: studentType,
          subjectId: item.subjectId,
          plan: item.plan,
        );
      } catch (e) {
        throw DecisionFailure(
          '${item.subjectId}: ${_message(e)}',
        );
      }
    }
  }

  /// Changes the subject-scoped plan entitlement for an already-
  /// registered subject: `activateFreePlan` first, then `upgrade` to the
  /// matching active plan document for PRO/MAX (same audited callable
  /// sequence as [addSubjects] — never direct Firestore writes).
  Future<void> changePlan({
    required String studentId,
    required bool isCenter,
    required String subjectId,
    required String plan,
  }) async {
    final String studentType =
        isCenter ? 'center_student' : 'guest';
    try {
      await _applyPlan(
        studentId: studentId,
        studentType: studentType,
        subjectId: subjectId,
        plan: plan,
      );
    } catch (e) {
      throw DecisionFailure(
        '$subjectId: ${_message(e)}',
      );
    }
  }

  /// Shared plan-entitlement sequence: FREE activates the free plan;
  /// PRO/MAX activate free first, then upgrade to the resolved plan doc.
  Future<void> _applyPlan({
    required String studentId,
    required String studentType,
    required String subjectId,
    required String plan,
  }) async {
    final String normalized = plan.toLowerCase();
    if (normalized == 'pro' || normalized == 'max') {
      await _functions.httpsCallable('activateFreePlan').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'studentType': studentType,
        },
      );
      final String planDocId = await _resolvePlanDocId(
        studentType: studentType,
        plan: normalized,
      );
      await _functions.httpsCallable('upgrade').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'newPlanId': planDocId,
        },
      );
    } else {
      await _functions.httpsCallable('activateFreePlan').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'studentType': studentType,
        },
      );
    }
  }
  /// Resolves the active plan document for ([studentType], [plan]) from
  /// the data-driven `plans` collection (`plan_key` suffix + matching
  /// `student_type`, `is_active`). No plan ids or eligibility rules are
  /// hardcoded; a missing paid plan surfaces the backend state honestly.
  Future<String> _resolvePlanDocId({
    required String studentType,
    required String plan,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('plans')
        .where('student_type', isEqualTo: studentType)
        .where('is_active', isEqualTo: true)
        .get();
    for (final doc in snap.docs) {
      final String key =
          ((doc.data()['plan_key'] as String?) ?? '').toLowerCase();
      if (key.endsWith('_$plan') || key == plan) return doc.id;
    }
    throw DecisionFailure(
      'لا توجد باقة $plan مفعّلة لهذا النوع من الطلاب.',
    );
  }
}

final studentProfileSubjectsControllerProvider =
    Provider<StudentProfileSubjectsController>((ref) {
  return StudentProfileSubjectsController(
    ref.watch(firebaseFunctionsProvider),
    ref.watch(firebaseFirestoreProvider),
  );
});
