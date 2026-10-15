import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/auth_providers.dart';
import 'auth_provider.dart';
import 'session_provider.dart';

/// Student forced-password-change controller.
///
/// Calls the EXISTING `changePassword` callable (functions/src/index.ts):
/// it requires `currentPassword` + a strong `newPassword` (>= 8 chars,
/// upper + lower + digit + special). The approved flow's temporary password
/// IS the student's current credential (they sign in with it), so callers
/// must pass the temporary password as [currentPassword].
///
/// Success contract (desync-proof by design): once the server write
/// succeeds, the temporary password is DEAD — retrying with it can only
/// fail. So this controller NEVER tries to keep the current session alive:
/// it signs out (same path as `SessionController.logout`) and the gate
/// routes to Login. The student signs in fresh with the NEW password, whose
/// claims already carry `force_password_change: false`, and lands straight
/// in the app. A post-write session failure therefore can never masquerade
/// as a "wrong password" error that traps the student in a retry loop.
///
/// On write failure (wrong temp, weak new password, throttle) the state
/// carries the error, the temp is still valid, and the caller must REMAIN
/// in the forced state (no navigation away, no dismissal).
///
/// State value: `true` once the forced change has completed successfully,
/// `false` otherwise.
final forcedPasswordChangeProvider =
    AsyncNotifierProvider<ForcedPasswordChangeController, bool>(
      ForcedPasswordChangeController.new,
    );

class ForcedPasswordChangeController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async => false;

  /// Submits the forced password change.
  ///
  /// Returns `true` on success (signed out — the gate routes to Login and
  /// the student signs in fresh with the NEW password).
  /// Returns `false` on write failure — inspect
  /// `ref.read(forcedPasswordChangeProvider).error` for the cause and keep
  /// the user in the forced state (the temp is still valid, retry is safe).
  Future<bool> submit({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = const AsyncLoading();

    // Phase 1 — server write. Failure here means the password did NOT
    // change (wrong temp, weak new password, throttle): report the error
    // and stay forced; retrying is safe because the temp is still alive.
    try {
      await FirebaseFunctions.instance.httpsCallable('changePassword').call({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } catch (error, stackTrace) {
      state = AsyncError<bool>(error, stackTrace);
      return false;
    }

    // Phase 2 — the server has rotated the password and the temp is dead.
    // Sign out through the standard session path so the gate routes to
    // Login unconditionally. A fresh sign-in with the NEW password carries
    // clean `force_password_change: false` claims — no stale-session
    // recovery, no retry loop. Post-write failures here are swallowed on
    // purpose: the write already succeeded, so surfacing an error would
    // lie to the student and invite retries with a dead temp.
    try {
      await ref.read(sessionProvider.notifier).logout();
    } catch (_) {
      ref.invalidate(customClaimsProvider);
      ref.invalidate(authProvider);
      ref.invalidate(sessionProvider);
    }

    state = const AsyncData<bool>(true);
    return true;
  }
}
