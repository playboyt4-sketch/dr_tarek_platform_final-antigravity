import 'package:cloud_functions/cloud_functions.dart';

import '../../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;

/// Callable-backed data source for student subject-access mutations.
///
/// This is the only place in the students feature allowed to import the
/// Firebase Functions SDK for these flows: providers depend on the
/// [SubjectAccessRepository] interface, widgets only `watch` state.
/// Every callable failure is mapped to a [DecisionFailure] carrying the
/// backend message so presentation can render it directly.
class SubjectAccessRemoteDataSource {
  final FirebaseFunctions _functions;

  const SubjectAccessRemoteDataSource(this._functions);

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

  Future<void> setAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool restore = false,
  }) async {
    try {
      await _functions.httpsCallable('setSubjectAccess').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'enabled': enabled,
          if (restore) 'isDeleted': false,
        },
      );
    } catch (e) {
      throw DecisionFailure(_message(e));
    }
  }

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

  Future<void> grantAccessWithPlan({
    required String studentId,
    required String subjectId,
    required String studentType,
    required String plan,
  }) async {
    try {
      await _functions.httpsCallable('grantSubjectAccessWithPlan').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'studentType': studentType,
          'plan': plan.toLowerCase(),
        },
      );
    } catch (e) {
      throw DecisionFailure(_message(e));
    }
  }

  Future<bool> isFreePlanEnabled() async {
    try {
      final HttpsCallableResult<Map<String, dynamic>> result =
          await _functions.httpsCallable('getSubjectAccessConfig').call(
        <String, Object>{},
      );
      return result.data['freePlanEnabled'] == true;
    } catch (e) {
      throw DecisionFailure(_message(e));
    }
  }
}
