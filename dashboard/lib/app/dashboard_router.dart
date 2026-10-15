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
/// enforced by the backend on every callable. The URL path is never an
/// authorization boundary: it only selects which role-specific entry the
/// session is checked against.

/// Canonical Dashboard URL paths (ADR-005).
///
/// Both paths resolve to the SAME shared [DashboardShell] architecture —
/// there is no separate Doctor or Admin dashboard. Served over Firebase
/// Hosting's SPA rewrite (`**` → `/index.html`), so deep links land here.
abstract final class DashboardRoutes {
  static const String root = '/';
  static const String doctor = '/doctor';
  static const String admin = '/admin';
}

/// Where a session lands for a given entry path.
///
/// Returned by [resolveDashboardDestination] and rendered by
/// [DashboardRouter]; kept as a pure function so the full role matrix is
/// unit-testable without widgets.
enum DashboardDestination {
  /// No session — show the login screen.
  login,

  /// Session exists but may not use this entry — rejection view.
  unauthorized,

  /// Approved staff session admitted to the shared shell.
  shell,
}

/// Pure entry decision: session + required role → destination.
///
/// - `expectedRole: 'doctor'` (`/doctor`) admits approved doctors only.
/// - `expectedRole: 'admin'` (`/admin`) admits approved admins only.
/// - `expectedRole: null` (root/legacy entry) admits any approved staff.
/// - Everything else (students, unapproved, unknown/null roles, wrong role
///   for the entry) fails closed to [DashboardDestination.unauthorized].
/// - No fallback mapping exists: unknown roles are never promoted, and
///   `teacher`/`dr` claims are never translated.
DashboardDestination resolveDashboardDestination(
  DashboardSession? session, {
  String? expectedRole,
}) {
  if (session == null) {
    return DashboardDestination.login;
  }
  if (!session.isStaff) {
    return DashboardDestination.unauthorized;
  }
  if (expectedRole != null && session.role != expectedRole) {
    return DashboardDestination.unauthorized;
  }
  return DashboardDestination.shell;
}

/// Builds the route for a Dashboard URL path.
///
/// Unknown paths fall through to the legacy session-driven entry
/// ([DashboardRoutes.root] behavior). Used by [DashboardApp] and covered
/// directly by routing tests.
Route<dynamic> buildDashboardRoute(RouteSettings settings) {
  final String path = settings.name ?? DashboardRoutes.root;
  if (path == DashboardRoutes.doctor) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => const DashboardRouter(expectedRole: 'doctor'),
    );
  }
  if (path == DashboardRoutes.admin) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => const DashboardRouter(expectedRole: 'admin'),
    );
  }
  return MaterialPageRoute<dynamic>(
    settings: settings,
    builder: (_) => const DashboardRouter(),
  );
}

class DashboardRouter extends ConsumerWidget {
  /// Role this entry requires (`'doctor'` for `/doctor`, `'admin'` for
  /// `/admin`, null for the legacy root entry). A mismatch never grants
  /// privileges — it renders the unauthorized view.
  final String? expectedRole;

  const DashboardRouter({super.key, this.expectedRole});

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
        switch (resolveDashboardDestination(value, expectedRole: expectedRole)) {
          case DashboardDestination.login:
            return const DashboardLoginScreen();
          case DashboardDestination.unauthorized:
            // Non-staff sessions are rejected at login time; this guard keeps
            // the home experience (and role-mismatched entries) out of reach
            // if claims change mid-session.
            return _UnauthorizedSessionView(
              userId: value?.userId ?? 'unknown',
            );
          case DashboardDestination.shell:
            return const DashboardShell();
        }
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
