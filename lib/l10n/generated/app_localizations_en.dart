// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Dr. Tarek El Araby Platform';

  @override
  String get navHome => 'Home';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get actionLogin => 'Login';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionSignOut => 'Sign out';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get loginPhoneHint => 'Phone number';

  @override
  String get loginPasswordHint => 'Password';

  @override
  String get sessionErrorTitle => 'Session error';

  @override
  String get roleUnavailableTitle => 'Role unavailable';

  @override
  String roleUnavailableMessage(String role) {
    return 'No approved destination is currently available for the $role role.';
  }

  @override
  String get pendingApprovalTitle => 'Account pending approval';

  @override
  String get pendingApprovalMessage =>
      'Your account is awaiting approval. You cannot access the platform yet.';

  @override
  String get rejectedTitle => 'Account rejected';

  @override
  String get rejectedMessage =>
      'This account was not approved. Please contact the platform administrator.';

  @override
  String get disabledTitle => 'Account disabled';

  @override
  String get disabledMessage =>
      'This account is disabled and cannot access the platform.';

  @override
  String get unauthorizedDeviceTitle => 'Unauthorized device';

  @override
  String get unauthorizedDeviceMessage =>
      'This device is not authorized for this account. Please use an approved device or contact support.';

  @override
  String get errorWrongCredentials => 'Invalid phone number or password.';

  @override
  String get errorNoInternet =>
      'Network unavailable. Check your internet connection and try again.';

  @override
  String get errorTimeout =>
      'The connection to the server timed out. Please try again.';

  @override
  String get errorServer => 'A server error occurred. Please try again later.';

  @override
  String get errorPermissionDenied =>
      'You do not have permission to perform this action.';

  @override
  String get errorTooManyRequests =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get errorApprovalPending => 'Your account is awaiting admin approval.';

  @override
  String get errorAccountDisabled => 'This account has been disabled.';

  @override
  String get errorPhoneExists =>
      'An account with this phone number already exists.';

  @override
  String get errorWrongCurrentPassword => 'The current password is incorrect.';

  @override
  String get errorWeakPassword =>
      'Password must be at least 8 characters and include upper and lower case letters, digits, and symbols.';

  @override
  String get errorValidation =>
      'The entered data is invalid. Please check it and try again.';

  @override
  String get errorNotFound => 'The requested item was not found.';

  @override
  String get errorSubscriptionRequired =>
      'An active subscription for this subject is required to access its content.';

  @override
  String get errorSubscriptionExpired =>
      'Your subscription to this subject has expired.';

  @override
  String get errorSubscriptionInactive =>
      'Your subscription to this subject is not active.';

  @override
  String get errorDisciplinaryDisabled =>
      'Your subscription has been suspended by the administration. Please contact support.';

  @override
  String get errorUnauthorizedDevice =>
      'This device is not authorized for this account.';

  @override
  String get errorGeneric => 'An unexpected error occurred. Please try again.';
}
