import '../entities/dashboard_session.dart';

/// Contract for the V1 authentication flow:
///
/// phone + password → `verifyPhonePassword` Cloud Function
///                  → Custom Token → `signInWithCustomToken`
///                  → claims refresh → [DashboardSession].
abstract class AuthRepository {
  /// Verifies credentials through the backend and establishes the Firebase
  /// Auth session. Returns the resolved session with refreshed claims.
  Future<DashboardSession> login({
    required String phoneNumber,
    required String password,
  });

  /// Ends the current Firebase Auth session.
  Future<void> logout();
}
