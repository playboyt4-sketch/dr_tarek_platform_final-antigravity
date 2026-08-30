import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import 'failure.dart';

/// Translates a [FailureCode] into a localized, user-friendly message.
/// This is the ONLY place where failure codes become display text.
String failureMessage(AppLocalizations l10n, FailureCode code) {
  return switch (code) {
    FailureCode.wrongCredentials => l10n.errorWrongCredentials,
    FailureCode.approvalPending => l10n.errorApprovalPending,
    FailureCode.accountDisabled => l10n.errorAccountDisabled,
    FailureCode.accountRejected => l10n.rejectedMessage,
    FailureCode.phoneAlreadyExists => l10n.errorPhoneExists,
    FailureCode.unauthorizedDevice => l10n.errorUnauthorizedDevice,
    FailureCode.wrongCurrentPassword => l10n.errorWrongCurrentPassword,
    FailureCode.weakPassword => l10n.errorWeakPassword,
    FailureCode.validation => l10n.errorValidation,
    FailureCode.permissionDenied => l10n.errorPermissionDenied,
    // Part B: the exact ratified Arabic message for a blocked section
    // deletion (05 Database v1.9 §9). Admin-facing only, so it is not in
    // the arb files.
    FailureCode.sectionHasActiveLectures =>
      'لا يمكن حذف القسم لوجود محاضرات نشطة بداخله. يرجى أرشفة المحاضرات أولاً.',
    // FINAL_DECISIONS §12: Center Free rolling 24-hour single-video wall.
    // Student-facing but plan-specific, so it stays out of the arb files
    // (same precedent as sectionHasActiveLectures).
    FailureCode.dailyVideoLimitReached =>
      'باقتك المجانية تسمح بمشاهدة فيديو واحد كل ٢٤ ساعة. أكمل أو استأنف نفس الفيديو، أو رقِّ الآن إلى Pro للمشاهدة غير المحدودة.',
    FailureCode.notFound => l10n.errorNotFound,
    FailureCode.tooManyRequests => l10n.errorTooManyRequests,
    FailureCode.subscriptionRequired => l10n.errorSubscriptionRequired,
    FailureCode.subscriptionExpired => l10n.errorSubscriptionExpired,
    FailureCode.subscriptionInactive => l10n.errorSubscriptionInactive,
    FailureCode.disciplinaryDisabled => l10n.errorDisciplinaryDisabled,
    FailureCode.noInternet => l10n.errorNoInternet,
    FailureCode.timeout => l10n.errorTimeout,
    FailureCode.server => l10n.errorServer,
    FailureCode.unknown => l10n.errorGeneric,
  };
}

/// Helper for widgets: resolves any error object into a friendly message.
String friendlyErrorMessage(BuildContext context, Object? error) {
  final l10n = AppLocalizations.of(context);
  if (error == null) return failureMessage(l10n, FailureCode.unknown);
  return failureMessage(l10n, Failure.from(error).code);
}
