import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../domain/entities/session_state.dart';
import '../providers/session_provider.dart';
import '../widgets/brand_signature_logo.dart';
import 'auth_gate.dart';

/// Screen 01 — Splash Screen.
///
/// If an authenticated session is already active on app launch, navigates
/// straight to the user's role home without waiting for the 5.8s brand hold or
/// routing through pre-login selection screens. Otherwise preserves the Figma
/// splash animation and hands off to [AppRoutes.userTypeSelection].
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const Duration _appearDelay = Duration(milliseconds: 300);
  static const Duration _fadeDuration = Duration(milliseconds: 800);
  static const Duration _navigationDelay = Duration(milliseconds: 5800);

  bool _visible = false;
  bool _navigated = false;
  Timer? _appearTimer;
  Timer? _navigationTimer;

  void _navigateIfAuthenticated(SessionState session) {
    if (_navigated || !mounted) return;
    if (session is! SessionAuthenticated) return;
    _navigated = true;
    _appearTimer?.cancel();
    _navigationTimer?.cancel();
    final dest =
        authGateDestinationForRole(session.user.role) ==
                AuthGateDestination.admin
            ? AppRoutes.adminHome
            : AppRoutes.studentHome;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.goNamed(dest);
    });
  }

  @override
  void initState() {
    super.initState();

    // Check immediately in case sessionProvider already resolved synchronously
    // or before SplashScreen mounted.
    final current = ref.read(sessionProvider);
    if (current case AsyncData<SessionState>(value: final state)) {
      if (state is SessionAuthenticated) {
        _navigateIfAuthenticated(state);
        return;
      }
    }

    _appearTimer = Timer(_appearDelay, () {
      if (!mounted || _navigated) return;
      setState(() => _visible = true);
    });

    _navigationTimer = Timer(_navigationDelay, () {
      if (!mounted || _navigated) return;
      final latest = ref.read(sessionProvider);
      if (latest case AsyncData<SessionState>(value: final state)
          when state is SessionAuthenticated) {
        _navigateIfAuthenticated(state);
        return;
      }
      _navigated = true;
      context.pushReplacementNamed(AppRoutes.userTypeSelection);
    });
  }

  @override
  void dispose() {
    _appearTimer?.cancel();
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SessionState>>(sessionProvider, (_, next) {
      if (next case AsyncData<SessionState>(value: final state)) {
        _navigateIfAuthenticated(state);
      }
    });

    final semantic = AppSemanticColors.of(context);
    return Scaffold(
      backgroundColor: semantic.canvas,
      body: AnimatedContainer(
        duration: _fadeDuration,
        curve: Curves.easeOut,
        color: _visible ? semantic.canvasWarm : semantic.canvas,
        child: Center(
          child: Hero(
            tag: 'brand_logo_signature',
            child: AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: _fadeDuration,
              curve: Curves.easeOut,
              child: BrandSignatureLogo(designPx: 128),
            ),
          ),
        ),
      ),
    );
  }
}
