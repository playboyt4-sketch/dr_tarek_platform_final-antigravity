import 'package:cloud_functions/cloud_functions.dart';

/// Maps backend errors to unified Arabic user-facing messages.
///
/// Raw exception details (`error.toString()`, stack traces, internal server
/// messages) are never shown to end users. Only the server-controlled
/// remaining-minutes value of a lockout response is preserved so users can
/// see their cooldown.

/// Pure code → Arabic mapper (unit-testable without platform exceptions).
String mapFunctionErrorCode(String code, String? detail, String fallback) {
  switch (code) {
    case 'unauthenticated':
      return 'بيانات الدخول غير صحيحة.';
    case 'permission-denied':
      return 'لا تملك صلاحية تنفيذ هذه العملية.';
    case 'resource-exhausted':
      final match = RegExp(r'in (\d+) minute').firstMatch(detail ?? '');
      if (match != null) {
        return 'عدد كبير من المحاولات الفاشلة. حاول بعد ${match.group(1)} دقيقة.';
      }
      return 'محاولات كثيرة جدًا، يرجى المحاولة لاحقًا.';
    case 'failed-precondition':
      return 'لا يمكن تنفيذ العملية في الحالة الحالية.';
    case 'already-exists':
      return 'هذا العنصر موجود بالفعل.';
    case 'not-found':
      return 'العنصر المطلوب غير موجود.';
    case 'invalid-argument':
      return 'تحقق من البيانات المدخلة ثم أعد المحاولة.';
    case 'deadline-exceeded':
      return 'انتهى الوقت المتاح لإكمال هذه العملية.';
    case 'unavailable':
    case 'internal':
      return 'الخدمة غير متاحة حاليًا، حاول لاحقًا.';
    default:
      return fallback;
  }
}

String friendlyFunctionErrorMessage(Object? error, String fallback) {
  if (error is FirebaseFunctionsException) {
    return mapFunctionErrorCode(error.code, error.message, fallback);
  }
  return fallback;
}
