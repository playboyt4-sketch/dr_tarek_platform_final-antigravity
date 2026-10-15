import '../repositories/password_reset_repository.dart';

/// Submits a V1 student password-reset request.
///
/// Thin pass-through: validation of the Egyptian format and per-phone
/// throttling live in the backend (`submitPasswordResetRequest` callable).
/// The presentation layer only guards empty input and duplicate taps.
class SubmitPasswordResetRequestUseCase {
  final PasswordResetRepository repository;

  const SubmitPasswordResetRequestUseCase(this.repository);

  Future<void> execute({required String phoneNumber}) {
    return repository.submitPasswordResetRequest(phoneNumber: phoneNumber);
  }
}
