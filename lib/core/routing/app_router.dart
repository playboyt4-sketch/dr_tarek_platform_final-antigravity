import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/screens/admin_home_screen.dart';
import '../../features/authentication/domain/entities/session_state.dart';
import '../../features/authentication/presentation/providers/session_provider.dart';
import '../../features/authentication/presentation/screens/auth_gate.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/new_student_welcome_screen.dart';
import '../../features/authentication/presentation/screens/splash_screen.dart';
import '../../features/authentication/presentation/screens/teacher_admin_selection_screen.dart';
import '../../features/authentication/presentation/screens/user_type_selection_screen.dart';
import '../../features/student_home/presentation/screens/student_home_screen.dart';
import 'app_routes.dart';

/// Central declarative router.
///
/// Boots strictly at the splash screen so [SplashScreen] runs its fade
/// animation first before handing off to [AppRoutes.userTypeSelection].
///
/// Web startup gate: browsers restore the previous URL (e.g.
/// `/#/user-type-selection`), and GoRouter honors that restored location —
/// `initialLocation` alone cannot force Splash. Until Splash has been
/// shown once per process, any non-splash location redirects there. The
/// gate is in-memory only (no SharedPreferences/storage/JS): hot reload
/// performs no navigation so it never re-arms, and once Splash is reached
/// all subsequent navigation — including any future deep links — is
/// untouched. Future approved deep-link routes that must survive a cold
/// start have to be exempted in [resolveBootRedirect].
bool _bootRedirectArmed = true;

/// Pure boot-gate decision (kept side-effect free for testing).
///
/// Returns the splash path when a cold start lands anywhere else while
/// the gate is armed, otherwise `null` (proceed normally).
@visibleForTesting
String? resolveBootRedirect({
  required bool bootArmed,
  required String location,
}) {
  if (!bootArmed) return null;
  if (location == AppRoutes.splashPath) return null;
  return AppRoutes.splashPath;
}

/// Pure session-gate decision (side-effect free, testable).
///
/// - Authenticated users are sent to their role home when they land on a
///   pre-login route (or on the other role's home).
/// - Unauthenticated sessions landing directly on a home route (e.g. a
///   restored web URL) are sent back to user-type selection.
/// - A `null` session (still loading / no data yet) never redirects: the
///   route's gate widget renders the loading state until it resolves.
@visibleForTesting
String? resolveSessionRedirect({
  required SessionState? session,
  required String location,
}) {
  const preLogin = {
    AppRoutes.splashPath,
    AppRoutes.userTypeSelectionPath,
    AppRoutes.newStudentWelcomePath,
    AppRoutes.loginPath,
    AppRoutes.teacherAdminSelectionPath,
  };
  const homes = {
    AppRoutes.studentHomePath,
    AppRoutes.adminHomePath,
  };

  if (session is SessionAuthenticated) {
    final dest =
        authGateDestinationForRole(session.user.role) ==
                AuthGateDestination.admin
            ? AppRoutes.adminHomePath
            : AppRoutes.studentHomePath;
    if (location == dest) return null;
    if (preLogin.contains(location)) return dest;
    if (homes.contains(location)) return dest;
    return null;
  }

  if (session == null) return null;
  if (homes.contains(location)) return AppRoutes.userTypeSelectionPath;
  return null;
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splashPath, // or '/'
  redirect: (context, state) {
    final next = resolveBootRedirect(
      bootArmed: _bootRedirectArmed,
      location: state.matchedLocation,
    );
    if (next == null && state.matchedLocation == AppRoutes.splashPath) {
      _bootRedirectArmed = false;
    }
    if (next != null) return next;
    // Session gate: read synchronously (no listen) — post-login screens
    // navigate explicitly via goNamed, so redirect only guards deep links,
    // back-button landings, and restored web URLs.
    final asyncSession = ProviderScope.containerOf(
      context,
    ).read(sessionProvider);
    final session = asyncSession is AsyncData<SessionState>
        ? asyncSession.value
        : null;
    return resolveSessionRedirect(
      session: session,
      location: state.matchedLocation,
    );
  },
  routes: <GoRoute>[
    GoRoute(
      path: AppRoutes.splashPath,
      name: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.userTypeSelectionPath,
      name: AppRoutes.userTypeSelection,
      // Figma splash exit: 800ms easeOut fade. Scoped to this route only so
      // the splash logo's Hero flight into the footer reads as one
      // continuous shared-element transition.
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const UserTypeSelectionScreen(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.newStudentWelcomePath,
      name: AppRoutes.newStudentWelcome,
      builder: (context, state) => const NewStudentWelcomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.loginPath,
      name: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.teacherAdminSelectionPath,
      name: AppRoutes.teacherAdminSelection,
      builder: (context, state) => const TeacherAdminSelectionScreen(),
    ),
    GoRoute(
      path: AppRoutes.studentHomePath,
      name: AppRoutes.studentHome,
      builder: (context, state) => const _StudentHomeRoute(),
    ),
    GoRoute(
      path: AppRoutes.adminHomePath,
      name: AppRoutes.adminHome,
      builder: (context, state) => const _AdminHomeRoute(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: const Color(0xFFFFFCF7),
    body: Center(
      child: Text(
        'Route not found: ${state.uri}',
        textAlign: TextAlign.center,
      ),
    ),
  ),
);

/// Session-gated student home route: renders the home only for an
/// authenticated student session, otherwise falls back to user-type
/// selection (the redirect above also bounces direct URL hits).
class _StudentHomeRoute extends ConsumerWidget {
  const _StudentHomeRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.maybeWhen(
      data: (state) =>
          state is SessionAuthenticated &&
                  authGateDestinationForRole(state.user.role) ==
                      AuthGateDestination.student
              ? StudentHomeScreen(user: state.user)
              : const UserTypeSelectionScreen(),
      orElse: () =>
          const Scaffold(backgroundColor: Color(0xFFFFFCF7)),
    );
  }
}

/// Session-gated admin home route (mirrors [_StudentHomeRoute]).
class _AdminHomeRoute extends ConsumerWidget {
  const _AdminHomeRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.maybeWhen(
      data: (state) =>
          state is SessionAuthenticated &&
                  authGateDestinationForRole(state.user.role) ==
                      AuthGateDestination.admin
              ? AdminHomeScreen(user: state.user)
              : const UserTypeSelectionScreen(),
      orElse: () =>
          const Scaffold(backgroundColor: Color(0xFFFFFCF7)),
    );
  }
}

class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  /// Canonical initial location of the app (mirrors [appRouter]).
  ///
  /// The app boots into [AppRoutes.splash] (`/splash`) so the splash screen
  /// runs its fade animation first before handing off to
  /// [AppRoutes.userTypeSelection].
  static const String initialLocation = AppRoutes.splashPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<SessionState>>(sessionProvider, (_, next) {
      final session = next is AsyncData<SessionState> ? next.value : null;
      if (session == null ||
          session is SessionAuthenticated ||
          session is SessionInitializing) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        
        void performPop() {
          if (!context.mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        }

        final route = ModalRoute.of(context);
        if (route?.animation != null && !route!.animation!.isCompleted) {
          late final AnimationStatusListener listener;
          listener = (status) {
            if (status == AnimationStatus.completed) {
              route.animation!.removeStatusListener(listener);
              performPop();
            }
          };
          route.animation!.addStatusListener(listener);
        } else {
          performPop();
        }
      });
    });

    final sessionState = ref.watch(sessionProvider);
    return AuthGate(sessionState: sessionState);
  }
}
