import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/dashboard_session.dart';
import '../../domain/validators/phone_validator.dart';
import 'auth_providers.dart';

/// Presentation states of the dashboard login form.
sealed class LoginState {
  const LoginState();
}

class LoginInitial extends LoginState {
  const LoginInitial();
}

class LoginSubmitting extends LoginState {
  const LoginSubmitting();
}

class LoginSuccess extends LoginState {
  final DashboardSession session;
  const LoginSuccess(this.session);
}

class LoginFailure extends LoginState {
  final Failure failure;

  /// Field-level validation message for the phone field, when applicable.
  final String? phoneError;

  /// Field-level validation message for the password field, when applicable.
  final String? passwordError;

  const LoginFailure(
    this.failure, {
    this.phoneError,
    this.passwordError,
  });
}

/// Controller driving the login screen. All authentication business rules
/// live in the domain/data layers; this class only orchestrates UI state.
class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginInitial();

  Future<void> submit({
    required String phoneNumber,
    required String password,
  }) async {
    if (state is LoginSubmitting) return;

    final phoneError = isValidEgyptianPhoneNumber(phoneNumber)
        ? null
        : 'Enter a valid Egyptian phone number (e.g. 01001234567).';
    final passwordError =
        password.isEmpty ? 'Please enter your password.' : null;

    if (phoneError != null || passwordError != null) {
      state = LoginFailure(
        const Failure(FailureCode.validation),
        phoneError: phoneError,
        passwordError: passwordError,
      );
      return;
    }

    state = const LoginSubmitting();

    try {
      final session = await ref.read(loginUseCaseProvider).execute(
            phoneNumber: phoneNumber,
            password: password,
          );

      // UX-level gate mirroring the approved staff-dashboard behavior: the
      // real boundary is server-side; non-staff sessions are rejected here
      // and signed out immediately.
      if (!session.isStaff) {
        await ref.read(authRepositoryProvider).logout();
        state = const LoginFailure(
          Failure(
            FailureCode.permissionDenied,
            debugDetail: 'non-staff session',
          ),
        );
        return;
      }

      state = LoginSuccess(session);
    } on Failure catch (failure) {
      state = LoginFailure(failure);
    } catch (error, stackTrace) {
      state = LoginFailure(Failure.from(error, stackTrace));
    }
  }

  void reset() {
    state = const LoginInitial();
  }
}

final loginControllerProvider =
    NotifierProvider.autoDispose<LoginController, LoginState>(
  LoginController.new,
);

/// Visual control only — no persistence semantics have been approved for
/// "Remember me" in the Dashboard experience (documented open decision).
/// Never store credentials here.
class RememberMeController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final rememberMeProvider = NotifierProvider<RememberMeController, bool>(
  RememberMeController.new,
);
