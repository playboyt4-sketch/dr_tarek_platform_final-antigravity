import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_typography.dart';
import '../../features/authentication/domain/entities/dashboard_session.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/authentication/presentation/screens/dashboard_login_screen.dart';
import 'shell/dashboard_shell.dart';

/// Session-driven routing for the dashboard experience.
///
/// Route guards are a UX/navigation convenience only — authorization is
/// enforced by the backend on every callable.
class DashboardRouter extends ConsumerWidget {
  const DashboardRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: SizedBox.shrink(),
      ),
      error: (Object error, StackTrace stackTrace) => const Scaffold(
        backgroundColor: AppColors.background,
        body: SizedBox.shrink(),
      ),
      data: (DashboardSession? value) {
        if (value == null) {
          return const DashboardLoginScreen();
        }
        // Non-staff sessions are rejected at login time; this guard keeps
        // the home experience out of reach if claims change mid-session.
        if (!value.isStaff) {
          return _UnauthorizedSessionView(userId: value.userId);
        }
        return const DashboardShell();
      },
    );
  }
}

class _UnauthorizedSessionView extends ConsumerWidget {
  final String userId;

  const _UnauthorizedSessionView({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'You do not have access to this dashboard.',
              style: AppTypography.loginSubtitle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  ref.read(authRepositoryProvider).logout(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
