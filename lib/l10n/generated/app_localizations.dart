import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'منصة د. طارق'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get navHome;

  /// No description provided for @navNotifications.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get navNotifications;

  /// No description provided for @actionLogin.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get actionLogin;

  /// No description provided for @actionRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get actionRetry;

  /// No description provided for @actionSignOut.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get actionSignOut;

  /// No description provided for @actionRefresh.
  ///
  /// In ar, this message translates to:
  /// **'تحديث'**
  String get actionRefresh;

  /// No description provided for @loginPhoneHint.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get loginPhoneHint;

  /// No description provided for @loginPasswordHint.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور'**
  String get loginPasswordHint;

  /// No description provided for @sessionErrorTitle.
  ///
  /// In ar, this message translates to:
  /// **'خطأ في الجلسة'**
  String get sessionErrorTitle;

  /// No description provided for @roleUnavailableTitle.
  ///
  /// In ar, this message translates to:
  /// **'الدور غير متاح'**
  String get roleUnavailableTitle;

  /// No description provided for @roleUnavailableMessage.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد وجهة متاحة حالياً لدور {role}.'**
  String roleUnavailableMessage(String role);

  /// No description provided for @pendingApprovalTitle.
  ///
  /// In ar, this message translates to:
  /// **'الحساب بانتظار الموافقة'**
  String get pendingApprovalTitle;

  /// No description provided for @pendingApprovalMessage.
  ///
  /// In ar, this message translates to:
  /// **'حسابك بانتظار موافقة الإدارة، لا يمكنك الوصول إلى المنصة بعد.'**
  String get pendingApprovalMessage;

  /// No description provided for @rejectedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض الحساب'**
  String get rejectedTitle;

  /// No description provided for @rejectedMessage.
  ///
  /// In ar, this message translates to:
  /// **'لم تتم الموافقة على هذا الحساب. يرجى التواصل مع إدارة المنصة.'**
  String get rejectedMessage;

  /// No description provided for @disabledTitle.
  ///
  /// In ar, this message translates to:
  /// **'الحساب معطل'**
  String get disabledTitle;

  /// No description provided for @disabledMessage.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحساب معطل ولا يمكنه الوصول إلى المنصة.'**
  String get disabledMessage;

  /// No description provided for @unauthorizedDeviceTitle.
  ///
  /// In ar, this message translates to:
  /// **'جهاز غير مصرح به'**
  String get unauthorizedDeviceTitle;

  /// No description provided for @unauthorizedDeviceMessage.
  ///
  /// In ar, this message translates to:
  /// **'هذا الجهاز غير مصرح به لهذا الحساب. استخدم جهازاً معتمداً أو تواصل مع الدعم.'**
  String get unauthorizedDeviceMessage;

  /// No description provided for @errorWrongCredentials.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف أو كلمة المرور غير صحيحة.'**
  String get errorWrongCredentials;

  /// No description provided for @errorNoInternet.
  ///
  /// In ar, this message translates to:
  /// **'تعذر الاتصال بالشبكة، تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.'**
  String get errorNoInternet;

  /// No description provided for @errorTimeout.
  ///
  /// In ar, this message translates to:
  /// **'انتهت مهلة الاتصال بالخادم، حاول مرة أخرى.'**
  String get errorTimeout;

  /// No description provided for @errorServer.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ في الخادم، حاول مرة أخرى لاحقاً.'**
  String get errorServer;

  /// No description provided for @errorPermissionDenied.
  ///
  /// In ar, this message translates to:
  /// **'ليس لديك صلاحية لتنفيذ هذا الإجراء.'**
  String get errorPermissionDenied;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In ar, this message translates to:
  /// **'محاولات كثيرة جداً، انتظر قليلاً ثم حاول مرة أخرى.'**
  String get errorTooManyRequests;

  /// No description provided for @errorApprovalPending.
  ///
  /// In ar, this message translates to:
  /// **'حسابك بانتظار موافقة الإدارة.'**
  String get errorApprovalPending;

  /// No description provided for @errorAccountDisabled.
  ///
  /// In ar, this message translates to:
  /// **'تم تعطيل هذا الحساب.'**
  String get errorAccountDisabled;

  /// No description provided for @errorPhoneExists.
  ///
  /// In ar, this message translates to:
  /// **'يوجد حساب مسجل بهذا الرقم بالفعل.'**
  String get errorPhoneExists;

  /// No description provided for @errorWrongCurrentPassword.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور الحالية غير صحيحة.'**
  String get errorWrongCurrentPassword;

  /// No description provided for @errorWeakPassword.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل وتشمل حروفاً كبيرة وصغيرة وأرقاماً ورموزاً.'**
  String get errorWeakPassword;

  /// No description provided for @errorValidation.
  ///
  /// In ar, this message translates to:
  /// **'البيانات المدخلة غير صحيحة، تحقق منها وحاول مرة أخرى.'**
  String get errorValidation;

  /// No description provided for @errorNotFound.
  ///
  /// In ar, this message translates to:
  /// **'العنصر المطلوب غير موجود.'**
  String get errorNotFound;

  /// No description provided for @errorSubscriptionRequired.
  ///
  /// In ar, this message translates to:
  /// **'يلزم اشتراك ساري في هذه المادة للوصول إلى المحتوى.'**
  String get errorSubscriptionRequired;

  /// No description provided for @errorSubscriptionExpired.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحية اشتراكك في هذه المادة.'**
  String get errorSubscriptionExpired;

  /// No description provided for @errorSubscriptionInactive.
  ///
  /// In ar, this message translates to:
  /// **'اشتراكك في هذه المادة غير مفعّل حالياً.'**
  String get errorSubscriptionInactive;

  /// No description provided for @errorDisciplinaryDisabled.
  ///
  /// In ar, this message translates to:
  /// **'تم إيقاف اشتراكك إدارياً، تواصل مع الإدارة.'**
  String get errorDisciplinaryDisabled;

  /// No description provided for @errorUnauthorizedDevice.
  ///
  /// In ar, this message translates to:
  /// **'هذا الجهاز غير مصرح به لهذا الحساب.'**
  String get errorUnauthorizedDevice;

  /// No description provided for @errorGeneric.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع، حاول مرة أخرى.'**
  String get errorGeneric;

  /// No description provided for @dangerZoneTitle.
  ///
  /// In ar, this message translates to:
  /// **'منطقة الخطر'**
  String get dangerZoneTitle;

  /// No description provided for @dangerZoneDescription.
  ///
  /// In ar, this message translates to:
  /// **'الإجراءات في هذه المنطقة لا يمكن التراجع عنها. يرجى الحذر.'**
  String get dangerZoneDescription;

  /// No description provided for @dangerZoneDeleteButton.
  ///
  /// In ar, this message translates to:
  /// **'حذف حسابي نهائيًا'**
  String get dangerZoneDeleteButton;

  /// No description provided for @deleteAccountDialogTitle.
  ///
  /// In ar, this message translates to:
  /// **'حذف الحساب نهائيًا'**
  String get deleteAccountDialogTitle;

  /// No description provided for @deleteAccountDialogWarning.
  ///
  /// In ar, this message translates to:
  /// **'⚠ هذا الإجراء نهائي ولا يمكن التراجع عنه'**
  String get deleteAccountDialogWarning;

  /// No description provided for @deleteAccountDialogDescription.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف حسابك وكل بياناتك نهائيًا: التقدم الدراسي، الملاحظات، النتائج، الرسائل، وصورة الملف الشخصي. تُحفظ سجلات الدفع لأغراض محاسبية بدون أي بيانات شخصية.'**
  String get deleteAccountDialogDescription;

  /// No description provided for @deleteAccountPasswordLabel.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور الحالية'**
  String get deleteAccountPasswordLabel;

  /// No description provided for @deleteAccountConfirmButton.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الحذف نهائيًا'**
  String get deleteAccountConfirmButton;

  /// No description provided for @deleteAccountSuccessMessage.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف حسابك بنجاح'**
  String get deleteAccountSuccessMessage;

  /// No description provided for @actionCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get actionCancel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
