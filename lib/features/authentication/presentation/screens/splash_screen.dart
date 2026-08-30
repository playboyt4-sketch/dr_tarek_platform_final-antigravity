import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/routing/app_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0;
  Timer? _fadeTimer;
  Timer? _navigateTimer;

  @override
  void initState() {
    super.initState();
    // 1. Initial delay: 300ms
    _fadeTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _opacity = 1.0);
    });

    // 2. Total Pre-navigation delay: 6100ms
    // (300ms delay + 800ms fade-in + 5000ms visible hold = 6100ms)
    _navigateTimer = Timer(const Duration(milliseconds: 6100), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800),
            pageBuilder: (context, animation, secondaryAnimation) => const AppRouter(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _navigateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: Center(
        child: Hero(
          tag: 'brand_logo_signature',
          child: Material(
            color: Colors.transparent,
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOut,
              child: Text(
                'Tarek el araby',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Gardenia Summer',
                  fontSize: context.rs(128),
                  color: const Color(0xFF000000),
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
