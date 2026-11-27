import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
import '../../domain/entities/session_state.dart';
import '../providers/session_provider.dart';
import '../widgets/brand_signature_logo.dart';

/// Screen 01 — Splash Screen.
///
/// Plays a smooth 1.6-second brand fade while warming up pre-login assets and
/// preloading saved-session subjects/posters in the background, then always
/// transitions reliably to [AppRoutes.userTypeSelection] (never skips directly
/// to Home and never hangs on the logo).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const Duration _appearDelay = Duration(milliseconds: 200);
  static const Duration _fadeDuration = Duration(milliseconds: 650);
  static const Duration _navigationDelay = Duration(milliseconds: 1600);

  bool _visible = false;
  bool _navigated = false;
  Timer? _appearTimer;
  Timer? _navigationTimer;

  void _triggerBackgroundPreload() {
    if (!mounted) return;
    for (final asset in const [
      'assets/images/new_student photo.png',
      'assets/images/current student photo.png',
      'assets/images/current_student_sign_in.png',
    ]) {
      unawaited(
        precacheImage(AssetImage(asset), context).catchError((_) {}),
      );
    }
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      unawaited(preloadSubjectsAndCovers(container, context));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerBackgroundPreload();
    });

    _appearTimer = Timer(_appearDelay, () {
      if (!mounted || _navigated) return;
      setState(() => _visible = true);
    });

    _navigationTimer = Timer(_navigationDelay, () {
      if (!mounted || _navigated) return;
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
    // Re-warm subjects/posters as soon as an existing saved session resolves
    // while Splash is visible.
    ref.listen<AsyncValue<SessionState>>(sessionProvider, (_, next) {
      if (next case AsyncData<SessionState>(value: final state)
          when state is SessionAuthenticated) {
        _triggerBackgroundPreload();
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
              child: const BrandSignatureLogo(designPx: 128),
            ),
          ),
        ),
      ),
    );
  }
}
