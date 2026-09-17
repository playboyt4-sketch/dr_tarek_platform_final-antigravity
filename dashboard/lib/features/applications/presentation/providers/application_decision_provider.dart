import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../domain/grade.dart';

/// A subject row available for approval-time access grants.
class SubjectOption {
  const SubjectOption({
    required this.id,
    required this.title,
    required this.gradeKey,
    this.isVisible = true,
  });

  final String id;
  final String title;
  final String? gradeKey;

  /// Live visibility (`is_visible`, falling back to `is_active`).
  /// Defaults to visible when the document carries neither flag.
  final bool isVisible;

  factory SubjectOption.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String title = (data['title'] as String?)?.trim() ?? '';
    final Object? visible = data['is_visible'] ?? data['is_active'];
    return SubjectOption(
      id: doc.id,
      title: title.isEmpty ? doc.id : title,
      gradeKey: normalizeGradeKey(data['grade']),
      isVisible: visible is bool ? visible : true,
    );
  }
}

/// Active (non-deleted) subjects eligible for approval-time access grants.
///
/// When [gradeKey] is known, only subjects of that grade are returned;
/// otherwise every active subject is returned. Mirrors the mobile
/// `students_management_screen` approval flow (FINAL_DECISIONS §13).
final gradeSubjectsProvider =
    StreamProvider.family<List<SubjectOption>, String?>((ref, gradeKey) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('subjects')
      .where('is_deleted', isEqualTo: false)
      .orderBy('display_order')
      .snapshots()
      .map(
        (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
            .map(SubjectOption.fromDoc)
            .where(
              (SubjectOption subject) =>
                  gradeKey == null || subject.gradeKey == gradeKey,
            )
            .toList(growable: false),
      );
});

/// Typed failure for approval/rejection decisions with an Arabic message
/// safe to render directly in the dialog.
class DecisionFailure implements Exception {
  const DecisionFailure(this.message);

  final String message;

  @override
  String toString() => 'DecisionFailure: $message';
}

/// Outcome of a successful [ApplicationDecisionController.approve] call.
class ApprovalResult {
  const ApprovalResult({
    required this.approved,
    required this.assignmentCount,
    required this.activatedCount,
    required this.activationFailures,
  });

  final bool approved;
  final int assignmentCount;
  final int activatedCount;
  final List<String> activationFailures;
}

/// Backend decision calls for joining applications.
///
/// Approve path is fully live: `approveStudent` sets the role, student type
/// and subject-access assignments; for free plans each enabled subject is
/// then activated through `activateFreePlan` (best effort).
///
/// Reject path calls the `rejectStudent` callable. When the backend has not
/// deployed it yet, a [DecisionFailure] with an explicit message is thrown
/// instead of failing silently.
class ApplicationDecisionController {
  const ApplicationDecisionController(this._functions);

  final FirebaseFunctions _functions;

  // Plan document IDs (not plan keys): the Guest plan is identified by
  // its document ID 'guest'. The per-subject 'plan' key ('free' vs paid)
  // below is genuinely a plan_key and stays 'free'.
  static const Set<String> freePlanKeys = <String>{
    'free',
    'guest',
  };

  Future<ApprovalResult> approve({
    required String studentId,
    required String studentType,
    required String planKey,
    required List<Map<String, Object>> subjectAccess,
  }) async {
    try {
      final HttpsCallableResult<Map<String, dynamic>> approval =
          await _functions.httpsCallable('approveStudent').call(
        <String, Object>{
          'studentId': studentId,
          'studentType': studentType,
          'subjectAccess': subjectAccess,
        },
      );
      final Map<String, dynamic> data = approval.data;
      final int assignmentCount =
          (data['assignmentCount'] as num?)?.toInt() ?? subjectAccess.length;

      int activated = 0;
      final List<String> activationFailures = <String>[];
      // Per-subject plans (review screen): only FREE-plan subjects are
      // activated here; paid plans are enabled via a recorded payment.
      // Legacy callers omit 'plan' and fall back to the global planKey.
      final bool perSubjectPlans =
          subjectAccess.any((Map<String, Object> item) => item['plan'] is String);
      if (perSubjectPlans || freePlanKeys.contains(planKey)) {
        final Iterable<String> enabledSubjectIds = subjectAccess
            .where(
              (Map<String, Object> item) =>
                  item['enabled'] == true &&
                  (!perSubjectPlans || (item['plan'] ?? 'free') == 'free'),
            )
            .map((Map<String, Object> item) => item['subjectId'] as String);
        for (final String subjectId in enabledSubjectIds) {
          try {
            await _functions.httpsCallable('activateFreePlan').call(
              <String, Object>{
                'studentId': studentId,
                'subjectId': subjectId,
                'studentType': studentType,
              },
            );
            activated += 1;
          } on FirebaseFunctionsException catch (e) {
            activationFailures.add('$subjectId: ${e.message ?? e.code}');
          }
        }
      }

      return ApprovalResult(
        approved: true,
        assignmentCount: assignmentCount,
        activatedCount: activated,
        activationFailures: activationFailures,
      );
    } on FirebaseFunctionsException catch (e) {
      throw DecisionFailure(_callableMessage(e));
    }
  }

  Future<void> reject({
    required String studentId,
    required String reason,
  }) async {
    try {
      await _functions.httpsCallable('rejectStudent').call(
        <String, Object>{
          'studentId': studentId,
          'reason': reason,
        },
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        throw const DecisionFailure(
          'خدمة الرفض غير مفعّلة في الخادم بعد (rejectStudent). '
          'تم حفظ سبب الرفض محلياً — فعّل الدالة السحابية لإتمام الرفض.',
        );
      }
      throw DecisionFailure(_callableMessage(e));
    }
  }

  String _callableMessage(FirebaseFunctionsException e) {
    final String? message = e.message;
    if (message != null && message.trim().isNotEmpty) return message;
    return switch (e.code) {
      'permission-denied' => 'لا تملك صلاحية تنفيذ هذا الإجراء.',
      'failed-precondition' => 'تعذّر تنفيذ الإجراء: حالة الطلب تغيّرت.',
      'not-found' => 'تعذّر العثور على الطالب أو المادة.',
      'invalid-argument' => 'بيانات القرار غير مكتملة.',
      _ => 'تعذّر تنفيذ القرار. حاول مرة أخرى.',
    };
  }
}

final applicationDecisionControllerProvider =
    Provider<ApplicationDecisionController>((ref) {
  return ApplicationDecisionController(ref.watch(firebaseFunctionsProvider));
});
