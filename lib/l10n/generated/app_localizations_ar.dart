// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'منصة د. طارق';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navNotifications => 'الإشعارات';

  @override
  String get actionLogin => 'تسجيل الدخول';

  @override
  String get actionRetry => 'إعادة المحاولة';

  @override
  String get actionSignOut => 'تسجيل الخروج';

  @override
  String get actionRefresh => 'تحديث';

  @override
  String get loginPhoneHint => 'رقم الهاتف';

  @override
  String get loginPasswordHint => 'كلمة المرور';

  @override
  String get sessionErrorTitle => 'خطأ في الجلسة';

  @override
  String get roleUnavailableTitle => 'الدور غير متاح';

  @override
  String roleUnavailableMessage(String role) {
    return 'لا توجد وجهة متاحة حالياً لدور $role.';
  }

  @override
  String get pendingApprovalTitle => 'الحساب بانتظار الموافقة';

  @override
  String get pendingApprovalMessage =>
      'حسابك بانتظار موافقة الإدارة، لا يمكنك الوصول إلى المنصة بعد.';

  @override
  String get rejectedTitle => 'تم رفض الحساب';

  @override
  String get rejectedMessage =>
      'لم تتم الموافقة على هذا الحساب. يرجى التواصل مع إدارة المنصة.';

  @override
  String get disabledTitle => 'الحساب معطل';

  @override
  String get disabledMessage => 'هذا الحساب معطل ولا يمكنه الوصول إلى المنصة.';

  @override
  String get unauthorizedDeviceTitle => 'جهاز غير مصرح به';

  @override
  String get unauthorizedDeviceMessage =>
      'هذا الجهاز غير مصرح به لهذا الحساب. استخدم جهازاً معتمداً أو تواصل مع الدعم.';

  @override
  String get errorWrongCredentials => 'رقم الهاتف أو كلمة المرور غير صحيحة.';

  @override
  String get errorNoInternet =>
      'تعذر الاتصال بالشبكة، تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.';

  @override
  String get errorTimeout => 'انتهت مهلة الاتصال بالخادم، حاول مرة أخرى.';

  @override
  String get errorServer => 'حدث خطأ في الخادم، حاول مرة أخرى لاحقاً.';

  @override
  String get errorPermissionDenied => 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';

  @override
  String get errorTooManyRequests =>
      'محاولات كثيرة جداً، انتظر قليلاً ثم حاول مرة أخرى.';

  @override
  String get errorApprovalPending => 'حسابك بانتظار موافقة الإدارة.';

  @override
  String get errorAccountDisabled => 'تم تعطيل هذا الحساب.';

  @override
  String get errorPhoneExists => 'يوجد حساب مسجل بهذا الرقم بالفعل.';

  @override
  String get errorWrongCurrentPassword => 'كلمة المرور الحالية غير صحيحة.';

  @override
  String get errorWeakPassword =>
      'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل وتشمل حروفاً كبيرة وصغيرة وأرقاماً ورموزاً.';

  @override
  String get errorValidation =>
      'البيانات المدخلة غير صحيحة، تحقق منها وحاول مرة أخرى.';

  @override
  String get errorNotFound => 'العنصر المطلوب غير موجود.';

  @override
  String get errorSubscriptionRequired =>
      'يلزم اشتراك ساري في هذه المادة للوصول إلى المحتوى.';

  @override
  String get errorSubscriptionExpired => 'انتهت صلاحية اشتراكك في هذه المادة.';

  @override
  String get errorSubscriptionInactive =>
      'اشتراكك في هذه المادة غير مفعّل حالياً.';

  @override
  String get errorDisciplinaryDisabled =>
      'تم إيقاف اشتراكك إدارياً، تواصل مع الإدارة.';

  @override
  String get errorUnauthorizedDevice => 'هذا الجهاز غير مصرح به لهذا الحساب.';

  @override
  String get errorGeneric => 'حدث خطأ غير متوقع، حاول مرة أخرى.';

  @override
  String get dangerZoneTitle => 'منطقة الخطر';

  @override
  String get dangerZoneDescription =>
      'الإجراءات في هذه المنطقة لا يمكن التراجع عنها. يرجى الحذر.';

  @override
  String get dangerZoneDeleteButton => 'حذف حسابي نهائيًا';

  @override
  String get deleteAccountDialogTitle => 'حذف الحساب نهائيًا';

  @override
  String get deleteAccountDialogWarning =>
      '⚠ هذا الإجراء نهائي ولا يمكن التراجع عنه';

  @override
  String get deleteAccountDialogDescription =>
      'سيتم حذف حسابك وكل بياناتك نهائيًا: التقدم الدراسي، الملاحظات، النتائج، الرسائل، وصورة الملف الشخصي. تُحفظ سجلات الدفع لأغراض محاسبية بدون أي بيانات شخصية.';

  @override
  String get deleteAccountPasswordLabel => 'كلمة المرور الحالية';

  @override
  String get deleteAccountConfirmButton => 'تأكيد الحذف نهائيًا';

  @override
  String get deleteAccountSuccessMessage => 'تم حذف حسابك بنجاح';

  @override
  String get actionCancel => 'إلغاء';
}
