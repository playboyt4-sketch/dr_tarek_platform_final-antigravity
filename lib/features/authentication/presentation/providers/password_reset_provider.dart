import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/password_reset_remote_datasource.dart';
import '../../data/repositories/password_reset_repository_impl.dart';
import '../../domain/repositories/password_reset_repository.dart';
import '../../domain/use_cases/submit_password_reset_request_use_case.dart';

final passwordResetRemoteDataSourceProvider =
    Provider<PasswordResetRemoteDataSource>((ref) {
      return PasswordResetRemoteDataSource(
        functions: FirebaseFunctions.instance,
      );
    });

final passwordResetRepositoryProvider = Provider<PasswordResetRepository>((
  ref,
) {
  return PasswordResetRepositoryImpl(
    remoteDataSource: ref.watch(passwordResetRemoteDataSourceProvider),
  );
});

final submitPasswordResetRequestUseCaseProvider =
    Provider<SubmitPasswordResetRequestUseCase>((ref) {
      return SubmitPasswordResetRequestUseCase(
        ref.watch(passwordResetRepositoryProvider),
      );
    });

final passwordResetControllerProvider =
    AsyncNotifierProvider<PasswordResetController, bool>(
      PasswordResetController.new,
    );

/// Presentation controller for the V1 password-reset request.
///
/// State is the submission flag: `false` initially, `true` once the backend
/// has accepted the request. Concurrent submissions are ignored so a
/// double-tap can never queue duplicate requests (backend per-phone
/// throttling remains the authoritative guard).
class PasswordResetController extends AsyncNotifier<bool> {
  bool _submitting = false;

  SubmitPasswordResetRequestUseCase get _useCase =>
      ref.read(submitPasswordResetRequestUseCaseProvider);

  @override
  Future<bool> build() async {
    return false;
  }

  /// Submits the request; returns true when the backend accepted it.
  ///
  /// A submission already in flight makes concurrent calls return the
  /// current value immediately (duplicate-tap guard). Failures rethrow as
  /// [Failure] for the caller to map through the project-standard
  /// friendly-message helper.
  Future<bool> submit({required String phoneNumber}) async {
    if (_submitting) {
      final current = state;
      return current is AsyncData<bool> ? current.value : false;
    }
    // First call can race provider initialization; settle build first so
    // the state assignments below never race it.
    try {
      await future;
    } catch (_) {
      // Ignored: [state] below carries the outcome (retry allowed).
    }
    if (_submitting) return false;
    _submitting = true;
    try {
      state = const AsyncLoading();
      await _useCase.execute(phoneNumber: phoneNumber);
      state = const AsyncData(true);
      return true;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    } finally {
      _submitting = false;
    }
  }

  void reset() {
    state = const AsyncData(false);
  }
}
