import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin/presentation/screens/admin_home_screen.dart';
import '../../../student_home/presentation/screens/student_home_screen.dart';
import '../../domain/entities/session_state.dart';
import '../providers/session_provider.dart';
import 'splash_screen.dart';
import 'user_type_selection_screen.dart';

enum AuthGateDestination { student, admin, blocked }

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
    return sessionState.when(
      loading: () => const SplashScreen(),
      error: (error, stackTrace) => _SessionMessage(
        title: 'Session error',
        message: error.toString().replaceFirst('Exception: ', ''),
        actionLabel: 'Retry',
        onAction: () => ref.read(sessionProvider.notifier).retry(),
      ),
      data: (session) => switch (session) {
        SessionInitializing() => const SplashScreen(),
        SessionUnauthenticated() => const UserTypeSelectionScreen(),
        SessionAuthenticated(:final user) => switch (authGateDestinationForRole(
          user.role,
        )) {
          AuthGateDestination.student => StudentHomeScreen(user: user),
          AuthGateDestination.admin => AdminHomeScreen(user: user),
          AuthGateDestination.blocked => _SessionMessage(
            title: 'Role unavailable',
            message:
                'This role does not have an available platform destination.',
            actionLabel: 'Sign out',
            onAction: () => ref.read(sessionProvider.notifier).logout(),
            userName: user.fullName,
          ),
        },
        SessionRoleBlocked(:final user, :final role) => _SessionMessage(
          title: 'Access unavailable',
          message:
              'No approved destination is currently available for the $role role.',
          actionLabel: 'Sign out',
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionPendingApproval(:final user) => _SessionMessage(
          title: 'Account pending approval',
          message:
              'Your account is awaiting approval. You cannot access the platform yet.',
          actionLabel: 'Sign out',
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionRejected(:final user) => _SessionMessage(
          title: 'Account rejected',
          message:
              'This account was not approved. Please contact the platform administrator.',
          actionLabel: 'Sign out',
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionDisabled(:final user) => _SessionMessage(
          title: 'Account disabled',
          message: 'This account is disabled and cannot access the platform.',
          actionLabel: 'Sign out',
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionUnauthorizedDevice(:final user) => _SessionMessage(
          title: 'Unauthorized device',
          message:
              'This device is not authorized for this account. Please use an approved device or contact support.',
          actionLabel: 'Sign out',
          onAction: () => ref.read(sessionProvider.notifier).logout(),
          userName: user.fullName,
        ),
        SessionError(:final error) => _SessionMessage(
          title: 'Session error',
          message: error.toString().replaceFirst('Exception: ', ''),
          actionLabel: 'Retry',
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
