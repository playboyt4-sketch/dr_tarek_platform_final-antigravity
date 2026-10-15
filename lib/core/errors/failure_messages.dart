import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import 'failure.dart';

/// Canonical Arabic copy for App Check attestation failures.
///
/// Deliberately neutral and flow-agnostic (NOT registration-specific):
/// [FailureCode.appCheckFailed] is shared transport-level taxonomy, so a
/// flow-specific string here would recreate the exact borrowed-copy bug
/// class this fixes (e.g. Login showing a "registration" message). Kept as
/// a const (same precedent as sectionHasActiveLectures below) so the legacy
/// mapper in `friendly_error_message.dart` reuses it instead of drifting.
const String appCheckFailureMessageAr =
    'تعذر التحقق من سلامة التطبيق، تحقق من اتصالك بالإنترنت وحاول مرة أخرى.';

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
    // Per-lecture student access: UI is approved, backend schema is not.
    // Staff-facing only, so it stays out of the arb files (same precedent
    // as sectionHasActiveLectures above).
    FailureCode.schemaNotApproved =>
      'Lecture access cannot be saved yet: per-lecture access has no approved backend schema. Selections are kept on this screen.',
    FailureCode.noInternet => l10n.errorNoInternet,
    FailureCode.timeout => l10n.errorTimeout,
    FailureCode.server => l10n.errorServer,
    // Attestation failure: neutral copy, never Login's wrongCredentials
    // string (BUG-AUTH fix). See [appCheckFailureMessageAr].
    FailureCode.appCheckFailed => appCheckFailureMessageAr,
    FailureCode.unknown => l10n.errorGeneric,
  };
}

/// Helper for widgets: resolves any error object into a friendly message.
String friendlyErrorMessage(BuildContext context, Object? error) {
  final l10n = AppLocalizations.of(context);
  if (error == null) return failureMessage(l10n, FailureCode.unknown);
  return failureMessage(l10n, Failure.from(error).code);
}
