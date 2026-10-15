/// Domain contract for the V1 forgot-password request flow.
///
/// The request is recorded server-side (a `password_reset_requests` document
/// plus admin/doctor notification); the password itself is later changed
/// manually from the Dashboard. There is no automated email/SMS/OTP reset.
abstract class PasswordResetRepository {
  /// Submits a password-reset request for [phoneNumber] (V1 Egyptian format,
  /// trimmed, without country code — no `+20` transformation here).
  ///
  /// Throws a [Failure] on backend/domain errors. Unknown or ineligible
  /// phones resolve normally (backend anti-enumeration); callers must not
  /// infer account existence from the outcome.
  Future<void> submitPasswordResetRequest({required String phoneNumber});
}
