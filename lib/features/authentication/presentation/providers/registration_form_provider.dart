import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/validators/egyptian_phone.dart';

/// In-progress answers for the New Student registration flow.
///
/// Covers the full 04 Features Registration Main Flow (steps 2–6):
/// `full_name`, `phone_number`, `profile_photo` (optional), `grade`, and
/// `password` — mapped to 05 Database `users.full_name`, `phone_number`,
/// `profile_photo`, and `grade`.
///
/// Fields for later steps are DECLARED here but not wired to any screen yet:
/// each upcoming step (Phone Number, Photo, Grade, Password) fills its own
/// field via a `setX` method on [RegistrationFormNotifier]. Nothing here
/// performs I/O: per 04 Features, the account is created (Cloud Function
/// call) only after the Password step — intermediate screens only mutate
/// this in-memory draft (Master Architecture: "UI contains no business
/// logic"; 07 Flutter Architecture: Presentation never touches Firebase).
class RegistrationDraft {
  /// Step 2 (Full Name screen). Always stored trimmed.
  final String fullName;

  /// Step 3 (Phone Number screen). Egyptian `01…` form, no country code.
  final String phoneNumber;

  /// Step 4 (Photo screen). Local file path; null when skipped (optional).
  final String? profilePhotoPath;

  /// Step 5 (Grade screen). One of
  /// `grade_one | grade_two | grade_three | grade_four`.
  final String? grade;

  /// Step 6 (Password screen). Kept in memory only for the final submit —
  /// never written to disk, never logged.
  final String? password;

  const RegistrationDraft({
    this.fullName = '',
    this.phoneNumber = '',
    this.profilePhotoPath,
    this.grade,
    this.password,
  });

  RegistrationDraft copyWith({
    String? fullName,
    String? phoneNumber,
    String? profilePhotoPath,
    String? grade,
    String? password,
  }) {
    return RegistrationDraft(
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      grade: grade ?? this.grade,
      password: password ?? this.password,
    );
  }
}

/// Holds the in-memory [RegistrationDraft] across registration steps.
///
/// The draft survives forward/back navigation between the step screens
/// (provider scope outlives individual routes). [reset] is for the terminal
/// step after a successful submit or an explicit restart.
class RegistrationFormNotifier extends Notifier<RegistrationDraft> {
  @override
  RegistrationDraft build() => const RegistrationDraft();

  /// Records the validated Full Name (step 2). Input is trimmed; validation
  /// itself lives in the screen's `Form` (03 UI & UX, Section 3.3).
  void setFullName(String value) {
    state = state.copyWith(fullName: value.trim());
  }

  /// Records the validated phone number (step 3). Input is normalized with
  /// [normalizeEgyptianPhone] (trim-only, V1 `01…` form, no country code);
  /// format validation itself lives in the screen's `Form` (08 Development
  /// Standards, Section 2.1). Uniqueness ("already registered") is NOT
  /// checked here — it is a server-side response at final submission
  /// (`registerNewStudent` → `FailureCode.phoneAlreadyExists`).
  void setPhoneNumber(String value) {
    state = state.copyWith(phoneNumber: normalizeEgyptianPhone(value));
  }

  /// Clears the whole draft (used after final submit / flow restart).
  void reset() => state = const RegistrationDraft();
}

/// Cross-step registration draft provider.
///
/// Scoped to the authentication feature
/// (`features/authentication/presentation/providers/`) and consumed by the
/// Name step now; the Phone Number, Photo, Grade, and Password screens
/// (next tasks in this flow) read/write their own fields on the same draft.
final registrationFormProvider =
    NotifierProvider<RegistrationFormNotifier, RegistrationDraft>(
  RegistrationFormNotifier.new,
);
