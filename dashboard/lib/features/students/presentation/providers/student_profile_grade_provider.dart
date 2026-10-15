import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;

/// Grade mutations for the Student Profile → Overview Grade Edit dialog.
///
/// The write goes through the atomic `changeStudentGrade` callable —
/// never a direct Firestore write — so `requireStudentAccessManager`
/// (doctor or delegated `admin_students`), `admin_audit_log`, and the
/// canonical `users/{studentId}.grade` field keep applying server-side
/// exactly as they do for the other student-management callables.
///
/// Atomicity: the grade update and the archival of the OLD grade's
/// subject-access assignments commit in a single server transaction —
/// either both land or neither does. New-grade subjects are deliberately
/// NOT auto-created here; the Admin picks them afterward via the
/// Subjects tab. Permission failures surface as [DecisionFailure] with
/// the backend message; the dialog renders it instead of pretending
/// success.
class StudentProfileGradeController {
  final FirebaseFunctions _functions;

  const StudentProfileGradeController(this._functions);

  String _message(Object error) {
    if (error is FirebaseFunctionsException) {
      final String? message = error.message;
      if (message != null && message.trim().isNotEmpty) return message;
      return switch (error.code) {
        'permission-denied' => 'لا تملك صلاحية تنفيذ هذا الإجراء.',
        'failed-precondition' => 'تعذّر تنفيذ الإجراء: حالة البيانات تغيّرت.',
        'not-found' => 'تعذّر العثور على الطالب.',
        'invalid-argument' => 'بيانات غير مكتملة.',
        _ => 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.',
      };
    }
    return 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';
  }

  /// Persists the canonical grade key (`grade_one` … `grade_four`) for
  /// [studentId] and atomically archives the old grade's subject-access
  /// assignments (see `changeStudentGrade`). Callers pass `GradeTheme`
  /// ids, which are canonical by construction — UI labels never cross
  /// this boundary.
  Future<void> updateGrade({
    required String studentId,
    required String grade,
  }) async {
    try {
      await _functions.httpsCallable('changeStudentGrade').call(
        <String, Object>{
          'studentId': studentId,
          'grade': grade,
        },
      );
    } catch (e) {
      throw DecisionFailure(_message(e));
    }
  }
}

final studentProfileGradeControllerProvider =
    Provider<StudentProfileGradeController>((ref) {
  return StudentProfileGradeController(ref.watch(firebaseFunctionsProvider));
});
