import '../entities/auth_user.dart';

sealed class SessionState {
  const SessionState();
}

final class SessionInitializing extends SessionState {
  const SessionInitializing();
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

final class SessionAuthenticated extends SessionState {
  final AuthUser user;
  final Map<String, dynamic> claims;

  const SessionAuthenticated({required this.user, required this.claims});
}

final class SessionRoleBlocked extends SessionState {
  final AuthUser user;
  final String role;

  const SessionRoleBlocked({required this.user, required this.role});
}

final class SessionPendingApproval extends SessionState {
  final AuthUser user;

  const SessionPendingApproval({required this.user});
}

final class SessionRejected extends SessionState {
  final AuthUser user;

  const SessionRejected({required this.user});
}

final class SessionDisabled extends SessionState {
  final AuthUser user;

  const SessionDisabled({required this.user});
}

final class SessionUnauthorizedDevice extends SessionState {
  final AuthUser user;

  const SessionUnauthorizedDevice({required this.user});
}

final class SessionError extends SessionState {
  final Object error;
  final StackTrace stackTrace;

  const SessionError({required this.error, required this.stackTrace});
}
