import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/design_tokens.dart';
import 'user_type_selection_screen.dart';

/// Design constants — copied verbatim from `splash_screen.md`. Raw
/// design-pixel values (393×852 canvas); consumed only via
/// `context.rs()` / `context.rsFont()`.
abstract final class _SplashScreenDesign {
  // ---- Brand signature (Gardenia Summer) ----
  static const signatureFontSize = 128.0;
  static const signatureColor = AppColors.black;

  // ---- Animation timing ----
  static const fadeInDelay = Duration(milliseconds: 300);
  static const fadeInDuration = Duration(milliseconds: 800);
  static const holdDuration = Duration(milliseconds: 5000);
  static const exitTransitionDuration = Duration(milliseconds: 800);
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();

    Future.delayed(_SplashScreenDesign.fadeInDelay, () {
      if (mounted) setState(() => _opacity = 1.0);
    });

    final navigateAfter = _SplashScreenDesign.fadeInDelay +
        _SplashScreenDesign.holdDuration +
        _SplashScreenDesign.fadeInDuration;

    Future.delayed(navigateAfter, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: _SplashScreenDesign.exitTransitionDuration,
          pageBuilder: (_, __, ___) => const UserTypeSelectionScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: Hero(
          tag: 'brand_logo_signature',
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: _SplashScreenDesign.fadeInDuration,
            curve: Curves.easeOut,
            child: Text(
              'Tarek el araby',
              textAlign: TextAlign.center,
              style: AppTypography.signature(
                context,
                designPx: _SplashScreenDesign.signatureFontSize,
                color: _SplashScreenDesign.signatureColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
