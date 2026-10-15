import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure, SubjectOption;
import '../../data/datasources/subject_access_remote_data_source.dart';
import '../../data/repositories/subject_access_repository_impl.dart';
import '../../domain/repositories/subject_access_repository.dart'
    show SubjectAccessRepository, SubjectGrantOutcome;

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
/// Writes go exclusively through [SubjectAccessRepository] (audited Cloud
/// Function callables: `setSubjectAccess` for toggles, the atomic
/// `grantSubjectAccessWithPlan` for grants — assignment + subscription in
/// one server transaction), which enforce `requireStudentAccessManager`
/// (doctor or delegated `admin_students`) server-side and write
/// `admin_audit_log` / analytics events. The client never invents
/// permission or audit identifiers.

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

/// Pure pick step (unit-testable): builds the commit list from ONLY the
/// subjects the Admin explicitly toggled ON in this dialog interaction.
///
/// Untouched or OFF rows produce NO write at all — never a disabled
/// (`enabled: false`) assignment row. Rationale: an unregistered subject
/// has no assignment document, and creating one just to record OFF clutters
/// the Subjects table (which lists every non-deleted assignment) with
/// plan-less rows while granting no entitlement. Already-registered
/// subjects are excluded (duplicate protection; the deterministic
/// `{studentId}_{subjectId}` assignment id plus
/// `enforceOneSubscriptionPerSubject` stay authoritative).
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
    // Only an explicit ON enters the write request. Untouched rows have
    // no entry in [toggles] and resolve to OFF → skipped (no write).
    // Explicit-OFF rows are likewise skipped: there is no assignment to
    // disable for an unregistered subject.
    if (toggles[subjectId] != true) return;
    picked.add(NewStudentSubject(
      subjectId: subjectId,
      enabled: true,
      plan: plans[subjectId] ?? 'free',
    ));
  }

  for (final SubjectOption subject in scope) {
    add(subject.id);
  }
  // Defensive: entries for ids that left the scope while the overlay was
  // open are still honored instead of silently dropped — when toggled ON.
  for (final String subjectId in toggles.keys) {
    add(subjectId);
  }
  // NOTE: [plans]-only entries (a plan chosen without ever toggling ON)
  // intentionally produce no write: the plan capsule is untappable while
  // the switch is off, so a plans-only entry can never reflect an Admin
  // grant intent.
  return picked;
}

/// Subject mutations for the Student Profile → Subjects tab.
///
/// Every write goes through [SubjectAccessRepository] (audited Cloud
/// Function callables — never direct Firestore writes) so
/// `requireStudentAccessManager` (doctor or delegated `admin_students`),
/// `admin_audit_log`, and analytics events keep applying exactly as they
/// do for the approval flow. Permission failures surface as
/// [DecisionFailure] with the backend message.
class StudentProfileSubjectsController {
  final SubjectAccessRepository _repository;

  const StudentProfileSubjectsController(this._repository);

  String _failureText(Object error) {
    if (error is DecisionFailure) return error.message;
    final String text = error.toString();
    const String prefix = 'DecisionFailure: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';
  }

  /// Immediate ON/OFF access change for an already-registered subject.
  /// The assignment stays registered; only `enabled` flips.
  Future<void> setAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
  }) async {
    await _repository.setAccess(
      studentId: studentId,
      subjectId: subjectId,
      enabled: enabled,
    );
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
    await _repository.removeSubject(
      studentId: studentId,
      subjectId: subjectId,
      enabled: enabled,
    );
  }

  /// Adds subjects picked in the add overlays. Already-registered
  /// (non-deleted) subjects are skipped — the deterministic
  /// `{studentId}_{subjectId}` assignment id plus
  /// `enforceOneSubscriptionPerSubject` remain authoritative against
  /// duplicates.
  ///
  /// Per-subject isolation (mirrors `ApplicationDecisionController.approve`
  /// at `application_decision_provider.dart`): each subject's call is
  /// wrapped in its own try/catch INSIDE the loop, so a failure on one
  /// subject never prevents the remaining subjects from being attempted.
  /// Every outcome — success or failure — is collected and returned; this
  /// method never throws for per-subject failures.
  ///
  /// Per enabled subject a single atomic `grantSubjectAccessWithPlan`
  /// call grants the assignment AND the subscription at the chosen plan
  /// tier together (no "activate free first, then upgrade" chain). OFF
  /// rows keep the `setSubjectAccess`-only short-circuit (no plan needed).
  Future<List<SubjectGrantOutcome>> addSubjects({
    required String studentId,
    required bool isCenter,
    required List<NewStudentSubject> subjects,
    required Set<String> alreadyRegistered,
    required Map<String, String> subjectTitles,
  }) async {
    final String studentType =
        isCenter ? 'center_student' : 'guest';
    final List<SubjectGrantOutcome> outcomes = <SubjectGrantOutcome>[];
    for (final NewStudentSubject item in subjects) {
      if (alreadyRegistered.contains(item.subjectId)) continue;
      final String name =
          subjectTitles[item.subjectId] ?? item.subjectId;
      try {
        if (!item.enabled) {
          await _repository.setAccess(
            studentId: studentId,
            subjectId: item.subjectId,
            enabled: false,
            restore: true,
          );
        } else {
          await _repository.grantAccessWithPlan(
            studentId: studentId,
            subjectId: item.subjectId,
            studentType: studentType,
            plan: item.plan,
          );
        }
        outcomes.add(SubjectGrantOutcome(
          subjectId: item.subjectId,
          subjectName: name,
          success: true,
        ));
      } catch (e) {
        outcomes.add(SubjectGrantOutcome(
          subjectId: item.subjectId,
          subjectName: name,
          success: false,
          errorMessage: _failureText(e),
        ));
      }
    }
    return outcomes;
  }

  /// Changes the subject-scoped plan entitlement for an already-
  /// registered subject via the atomic `grantSubjectAccessWithPlan`
  /// callable (assignment + subscription retargeted together — never
  /// direct Firestore writes).
  Future<void> changePlan({
    required String studentId,
    required bool isCenter,
    required String subjectId,
    required String plan,
  }) async {
    final String studentType =
        isCenter ? 'center_student' : 'guest';
    try {
      await _repository.grantAccessWithPlan(
        studentId: studentId,
        subjectId: subjectId,
        studentType: studentType,
        plan: plan,
      );
    } catch (e) {
      throw DecisionFailure(
        '$subjectId: ${_failureText(e)}',
      );
    }
  }
}

/// Firebase-backed [SubjectAccessRepository] for the students feature.
///
/// Riverpod's graph is the DI mechanism (07 §7): providers depend on the
/// interface, never on Firebase types directly.
final subjectAccessRepositoryProvider =
    Provider<SubjectAccessRepository>((ref) {
  return SubjectAccessRepositoryImpl(
    SubjectAccessRemoteDataSource(ref.watch(firebaseFunctionsProvider)),
  );
});

/// Whether the FREE tier may currently be granted
/// (`system_settings.free_plan_enabled`), read through the audited
/// `getSubjectAccessConfig` callable. The UI uses this to hide/disable
/// the FREE segment instead of letting the Admin hit the server rejection
/// at save time; the server check remains the true gate.
///
/// One-shot fetch (not a live stream): a callable has no Firestore
/// snapshot stream, so an out-of-app settings change does NOT push here.
/// `autoDispose` re-fetches on next navigation to a watching screen, and
/// each plan dialog additionally does a `ref.refresh(...future)` before
/// opening so the opened dialog reflects the current server value
/// without requiring a full page reload.
final freePlanAvailabilityProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(subjectAccessRepositoryProvider).isFreePlanEnabled();
});

final studentProfileSubjectsControllerProvider =
    Provider<StudentProfileSubjectsController>((ref) {
  return StudentProfileSubjectsController(
    ref.watch(subjectAccessRepositoryProvider),
  );
});
