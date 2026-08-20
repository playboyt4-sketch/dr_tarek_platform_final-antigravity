import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/auth_providers.dart';
import '../../../device_binding/presentation/providers/device_binding_provider.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/session_state.dart';
import 'auth_provider.dart';

final sessionProvider = AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    try {
      return await _bootstrap();
    } catch (error, stackTrace) {
      return SessionError(error: error, stackTrace: stackTrace);
    }
  }

  Future<SessionState> _bootstrap() async {
    final user = await ref.watch(authProvider.future);
    if (user == null) {
      return const SessionUnauthenticated();
    }

    final claims =
        await ref.watch(customClaimsProvider.future) ??
        const <String, dynamic>{};

    final accountState = resolveAccountSessionState(user: user, claims: claims);
    if (accountState != null) {
      return accountState;
    }

    final deviceBindingController = ref.read(deviceBindingProvider.notifier);
    await deviceBindingController.validateDevice(userId: user.id);

    final deviceState = ref.read(deviceBindingProvider);
    if (deviceState.hasError) {
      throw deviceState.error ?? Exception('Device authorization failed.');
    }
    if (deviceState.value != true) {
      return SessionUnauthorizedDevice(user: user);
    }

    final role = user.role.trim().toLowerCase();
    if (role != 'student' && role != 'admin') {
      return SessionRoleBlocked(user: user, role: role);
    }

    return SessionAuthenticated(user: user, claims: claims);
  }

  Future<void> logout() async {
    await ref.read(authProvider.notifier).logout();
    ref.invalidateSelf();
  }

  void retry() {
    ref.invalidateSelf();
  }
}

SessionState? resolveAccountSessionState({
  required AuthUser user,
  required Map<String, dynamic> claims,
}) {
  final accountStatus = user.accountStatus.trim().toLowerCase();
  if (accountStatus == 'disabled') {
    return SessionDisabled(user: user);
  }

  final approvalStatus = user.approvalStatus.trim().toLowerCase();
  if (approvalStatus == 'rejected') {
    return SessionRejected(user: user);
  }

  final approvedClaim = claims['approved'];
  final isApproved = approvedClaim is bool
      ? approvedClaim
      : approvalStatus == 'approved';
  if (!isApproved) {
    return SessionPendingApproval(user: user);
  }

  return null;
}
