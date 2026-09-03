import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'new_student_name_screen.dart';

class NewStudentWelcomeScreen extends StatelessWidget {
  const NewStudentWelcomeScreen({super.key});

  // CTA uses the Design-System Solid Primary token: AppColors.buttonSolid (#1D4ED8).

  /// Brand red for the signature (#DC2626 = AppColors.grade4Canvas).
  static const _signatureRed = AppColors.grade4Canvas;

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreen(
      backgroundColor: AppColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top content group
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Top spacing below safe-area (≈ 50 px in reference) ──
              SizedBox(height: context.rs(50)),

              // ── Hero illustration ──────────────────────────────────
              Semantics(
                label: 'Welcome illustration',
                image: true,
                excludeSemantics: true,
                child: ResponsiveImage(
                  assetPath: 'assets/images/New Student - Welcome photo .png',
                  designWidth: 369,
                  designHeight: 395,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.school,
                      size: context.rs(80),
                      color: AppColors.buttonSolid,
                    );
                  },
                ),
              ),

              SizedBox(height: context.rs(32)),

              // ── Welcome title ──────────────────────────────────────
              // "Welcome to our community with" — 28 px / Regular / #111827
              Text(
                'Welcome to our community\nwith',
                textAlign: TextAlign.center,
                style: AppTypography.titleLarge(
                  context,
                  color: AppColors.darkText,
                ),
              ),

              SizedBox(height: context.rs(16)),

              // ── Brand signature — Gardenia Summer 128px / #DC2626 ──
              Text(
                'Tarek el araby',
                textAlign: TextAlign.center,
                style: AppTypography.signature(
                  context,
                  designPx: 128,
                  color: _signatureRed,
                ),
              ),
            ],
          ),

          // ── Primary CTA — 345 × 56, pill, #1D4ED8 (Solid Primary) ──
          Padding(
            padding: EdgeInsets.only(bottom: context.rs(42)),
            child: ResponsiveButton(
              onPressed: () => _openRegistration(context),
              height: AppComponentDimens.buttonHeight,
              minWidth: AppComponentDimens.buttonWidth,
              backgroundColor: AppColors.buttonSolid,
              borderRadius: AppShapes.radiusFull,
              child: Text(
                'Get started',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFontFamilies.googleSansFlex,
                  fontSize: context.rsFont(20),
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                  height: 26 / 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openRegistration(BuildContext context) {
    // Horizontal push-left slide transition (300 ms) → NewStudentNameScreen
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NewStudentNameScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Push-left: new screen slides in from the right.
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: Curves.easeInOut),
          );
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }
}