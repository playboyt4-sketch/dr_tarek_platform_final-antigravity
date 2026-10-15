import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

// ---------------------------------------------------------------------------
// Design constants for the "New Student - End" step (Figma, 393x852 canvas).
// Raw design-pixel values from Figma dev mode, consumed exclusively via
// context.rs() / context.rsV() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere. Pattern mirrors
// NewStudentWelcomeScreen / NewStudentNameScreen: Scaffold + SafeArea +
// SingleChildScrollView + ConstrainedBox(minHeight: viewportHeight) +
// SizedBox(393x852) + Stack of exact Positioned coordinates.
// ---------------------------------------------------------------------------
abstract final class _EndDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Illustration: 369x348 at (12, 50), corner radius 35.
  // NO back button on this screen per Figma.
  static const illustrationX = 12.0;
  static const illustrationY = 50.0;
  static const illustrationWidth = 369.0;
  static const illustrationHeight = 348.0;
  static const illustrationRadius = 35.0;

  // Title frame: 393x82 at y430 ("Your request is under review"), centered.
  static const titleY = 430.0;
  static const titleWidth = 393.0;
  static const titleHeight = 82.0;

  // Subtitle frame: 393x63 at y537, centered.
  static const subtitleY = 537.0;
  static const subtitleWidth = 393.0;
  static const subtitleHeight = 63.0;

  // Primary CTA: 345 wide at (24, 754), pops to first route.
  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
  static const buttonHeight = 56.0;
}

/// Terminal confirmation state shown after a successful New Student
/// registration submission (Waiting for Approval).
///
/// Presentation-only: performs no registration, no Firebase/Firestore/Auth
/// access, no approval or subscription changes, no polling or timers.
/// Navigation into this screen is owned by the existing registration flow
/// ([NewStudentPasswordScreen] / [StudentRegistrationWizard]); the existing
/// `Done` → `popUntil(isFirst)` exit is preserved verbatim (see Open
/// Question in `docs/notion/03_UI_UX.md` §3.8 — Figma frame shows no CTA).
class NewStudentEndScreen extends StatelessWidget {
  const NewStudentEndScreen({super.key});

  /// Warm off-white canvas per Figma (`#FFFCF7`). Kept as a screen-local
  /// constant to match [NewStudentNameScreen.backgroundColor]; no global
  /// duplicate token is introduced (none exists in [AppColors]).
  static const Color backgroundColor = Color(0xFFFFFCF7);
  static const Color primaryBlue = Color(0xFF1D4ED8);

  @override
  Widget build(BuildContext context) {
    // Same viewport math as the Welcome/Name screens: the fixed 393x852
    // Stack lives INSIDE the SafeArea, so Figma's y-coords (measured from
    // the canvas top, status-bar chrome included) land correctly without
    // any manual top/bottom padding to tune.
    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;

    return Scaffold(
      backgroundColor: NewStudentEndScreen.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR - this is an English-only screen.
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_EndDesign.canvasWidth),
                height: context.rsV(_EndDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Top Illustration (No Back Button per Figma) ---
                    // Figma 12,50 369x348 r35.
                    Positioned(
                      left: context.rs(_EndDesign.illustrationX),
                      top: context.rsV(_EndDesign.illustrationY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_EndDesign.illustrationRadius),
                        ),
                        child: SizedBox(
                          width: context.rs(_EndDesign.illustrationWidth),
                          height:
                              context.rsV(_EndDesign.illustrationHeight),
                          child: Image.asset(
                            'assets/images/New Student - End photo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFFF3F4F6),
                              child: const Icon(
                                Icons.access_time_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 2. Title (Figma y430, 393x82, centered). ---
                    // Figma: Google Sans Flex 28px regular black, lh 36px.
                    Positioned(
                      top: context.rsV(_EndDesign.titleY),
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        width: context.rs(_EndDesign.titleWidth),
                        height: context.rsV(_EndDesign.titleHeight),
                        child: Center(
                          child: Text(
                            'Your request is\nunder review',
                            textAlign: TextAlign.center,
                            style: AppTypography.titleLarge(
                              context,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 3. Explanation Subtitle (Figma y537, 393x63). ---
                    // Figma: Google Sans Flex 14px regular #9A9A9A, lh 20px.
                    Positioned(
                      top: context.rsV(_EndDesign.subtitleY),
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        width: context.rs(_EndDesign.subtitleWidth),
                        height: context.rsV(_EndDesign.subtitleHeight),
                        child: Center(
                          child: Text(
                            'We are reviewing your request\nyou will be notified soon',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyRegular(
                              context,
                              color: const Color(0xFF9A9A9A),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 4. Pinned Primary Bottom Button ("Done"). ---
                    // Figma 24,754 w345.
                    Positioned(
                      left: context.rs(_EndDesign.buttonX),
                      top: context.rsV(_EndDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_EndDesign.buttonWidth),
                        height: context.rsV(_EndDesign.buttonHeight),
                        child: ElevatedButton(
                          onPressed: () {
                            // Close registration flow and return to initial gate
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                NewStudentEndScreen.primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                context.rs(9999),
                              ),
                            ),
                          ),
                          child: Text(
                            'Done',
                            style: AppTypography.titleMedium(
                              context,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
