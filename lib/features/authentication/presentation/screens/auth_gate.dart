import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/errors/failure_messages.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../admin/presentation/screens/admin_home_screen.dart';
import '../../../student_home/presentation/screens/student_home_screen.dart';
import '../../domain/entities/session_state.dart';
import '../providers/session_provider.dart';

import 'user_type_selection_screen.dart';

enum AuthGateDestination { student, admin, blocked }

/// Maps any session error object into a localized, user-friendly message.
/// Raw exception details are never shown to users.
String friendlySessionError(AppLocalizations l10n, Object? error) {
  if (error == null) return failureMessage(l10n, FailureCode.unknown);
  return failureMessage(l10n, Failure.from(error).code);
}

AuthGateDestination authGateDestinationForRole(String role) {
  return switch (role.trim().toLowerCase()) {
    'student' => AuthGateDestination.student,
    'admin' => AuthGateDestination.admin,
    _ => AuthGateDestination.blocked,
  };
}

class AuthGate extends ConsumerWidget {
  final AsyncValue<SessionState> sessionState;

  const AuthGate({super.key, required this.sessionState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return sessionState.when(
      loading: () => const Scaffold(backgroundColor: Color(0xFFFFFCF7)),
      error: (error, stackTrace) => _SessionMessage(
        title: l10n.sessionErrorTitle,
        message: friendlySessionError(l10n, error),
        actionLabel: l10n.actionRetry,
        onAction: () => ref.read(sessionProvider.notifier).retry(),
      ),
      data: (session) => switch (session) {
        SessionInitializing() => const Scaffold(backgroundColor: Color(0xFFFFFCF7)),
        SessionUnauthenticated() => const UserTypeSelectionScreen(),
        SessionAuthenticated(:final user) => switch (authGateDestinationForRole(
          user.role,
        )) {
          AuthGateDestination.student => StudentHomeScreen(user: user),
          AuthGateDestination.admin => AdminHomeScreen(user: user),
          AuthGateDestination.blocked => _SessionMessage(
            title: l10n.roleUnavailableTitle,
            message: l10n.roleUnavailableMessage(user.role),
            actionLabel: l10n.actionSignOut,
            onAction: () => ref.read(sessionProvider.notifier).logout(),
            userName: user.fullName,
          ),
        },
        SessionRoleBlocked(:final user, :final role) => _SessionMessage(
          title: l10n.roleUnavailableTitle,
          message: l10n.roleUnavailableMessage(role),
          actionLabel: l10n.actionSignOut,
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionPendingApproval(:final user) => _SessionMessage(
          title: l10n.pendingApprovalTitle,
          message: l10n.pendingApprovalMessage,
          actionLabel: l10n.actionSignOut,
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionRejected(:final user) => _SessionMessage(
          title: l10n.rejectedTitle,
          message: l10n.rejectedMessage,
          actionLabel: l10n.actionSignOut,
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionDisabled(:final user) => _SessionMessage(
          title: l10n.disabledTitle,
          message: l10n.disabledMessage,
          actionLabel: l10n.actionSignOut,
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionUnauthorizedDevice(:final user) => _SessionMessage(
          title: l10n.unauthorizedDeviceTitle,
          message: l10n.unauthorizedDeviceMessage,
          actionLabel: l10n.actionSignOut,
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionError(:final error) => _SessionMessage(
          title: l10n.sessionErrorTitle,
          message: friendlySessionError(l10n, error),
          actionLabel: l10n.actionRetry,
          onAction: () => ref.read(sessionProvider.notifier).retry(),
        ),
      },
    );
  }
}

class _SessionMessage extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? userName;

  const _SessionMessage({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (userName != null) ...[
                  const SizedBox(height: 8),
                  Text(userName!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
