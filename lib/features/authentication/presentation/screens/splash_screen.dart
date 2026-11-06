import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../widgets/brand_signature_logo.dart';


/// Screen 01 — Splash Screen.
///
/// Figma states (393 x 852 reference frame):
/// - Splash Start: `#FFFFFF` background, logo opacity 0.
/// - Splash End: `#FFFCF7` background, logo opacity 1.
///
/// Appearance: 300ms delay, then an 800ms `Curves.easeOut` fade of the
/// logo to opacity 1. The background crossfades white -> cream over the
/// same 800ms window (implementation decision: Figma specifies only the
/// two endpoint colors, not the interpolation). No scale animation.
///
/// Hold: the logo stays fully visible until 5800ms after init (Figma:
/// 5000ms hold, navigate at 5800ms), then hands off via the existing
/// GoRouter mechanism. The logo is wrapped in
/// `Hero(tag: 'brand_logo_signature')` so it flies continuously into the
/// User Type Selection footer instead of disappearing and reappearing.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});


  @override
  State<SplashScreen> createState() => _SplashScreenState();
}


class _SplashScreenState extends State<SplashScreen> {
  // Figma-specified timing.
  static const Duration _appearDelay = Duration(milliseconds: 300);
  static const Duration _fadeDuration = Duration(milliseconds: 800);
  // Figma: 5000ms hold, navigate at 5800ms.
  static const Duration _navigationDelay = Duration(milliseconds: 5800);

  bool _visible = false;


  @override
  void initState() {
    super.initState();


    Future.delayed(_appearDelay, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });


    Future.delayed(_navigationDelay, () {
      if (!mounted) return;
      context.pushReplacementNamed(AppRoutes.userTypeSelection);
    });
  }


  @override
  Widget build(BuildContext context) {
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
