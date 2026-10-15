import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/brand_signature_logo.dart';
import 'new_student_name_screen.dart';

// ---------------------------------------------------------------------------
// Design constants for the "New Student - Welcome" step (Figma node 35:18).
// All values are raw design-pixel values from Figma, consumed exclusively
// via context.rs() / context.rsV() / context.rsFont() (through
// AppTypography) — identical to Figma at the 393x852 reference, proportionally
// preserved elsewhere. Pattern mirrors NewStudentNameScreen (sibling step).
// ---------------------------------------------------------------------------
abstract final class _WelcomeDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Hero photo: 369x395 at (12, 50), corner radius 35.
  // Figma fill: IMAGE scaleMode STRETCH (objectFit fill) with
  // cropTransform [[0.8184732794761658, 0, 0.09045857191085815],
  //                [0, 0.49311739206314087, 0.05046232417225838]].
  // Derived cover alignment (exact, not a generic center approximation):
  //   ax = (2*tx + sx - 1) / (1 - sx) ~= -0.0034
  //   ay = (2*ty + sy - 1) / (1 - sy) ~= -0.8009
  static const heroX = 12.0;
  static const heroY = 50.0;
  static const heroWidth = 369.0;
  static const heroHeight = 395.0;
  static const heroCornerRadius = 35.0;
  static const heroAlignX = -0.0034;
  static const heroAlignY = -0.8009;
  static const heroAsset = 'assets/images/New Student - Welcome photo.png';

  // Floating back button: 44x44 at (24, 54), asset button/back.
  static const backButtonX = 24.0;
  static const backButtonY = 54.0;
  static const backButtonSize = 44.0;
  static const backAsset = 'assets/images/back.svg';

  // Headline frame: 393x71 at y469, title/large 28 Regular / 36 centered.
  static const titleY = 469.0;

  // Signature frame: 393x95 at y600, Gardenia Summer 128, #DC2626, centered.
  static const signatureY = 600.0;
  static const signatureWidth = 393.0;
  static const signatureHeight = 95.0;
  static const signatureRed = Color(0xFFDC2626);

  // Primary button/Style3: 345 wide at (24, 754), padding 24x14,
  // bg #1D4ED8, 1px rgba(255,255,255,0.30), backdrop blur 12, radius 9999.
  // Label "Get Start", title/medium 20 Regular / 26, white, centered.
  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
  static const buttonBg = Color(0xFF1D4ED8);
  static const buttonBorder = Color(0x4DFFFFFF); // 30% white
  static const buttonBlur = 12.0;
  static const buttonRadius = 9999.0;
  static const buttonPaddingH = 24.0;
  static const buttonPaddingV = 14.0;
}

// ---------------------------------------------------------------------------
class NewStudentWelcomeScreen extends StatelessWidget {
  const NewStudentWelcomeScreen({super.key});

  void _onGetStartPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewStudentNameScreen(),
      ),
    );
  }

  void _onBackPressed(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR - this is an English-only screen.
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_WelcomeDesign.canvasWidth),
                height: context.rsV(_WelcomeDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Hero photo (Figma 12,50 369x395 r35).
                    Positioned(
                      left: context.rs(_WelcomeDesign.heroX),
                      top: context.rsV(_WelcomeDesign.heroY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_WelcomeDesign.heroCornerRadius),
                        ),
                        child: SizedBox(
                          width: context.rs(_WelcomeDesign.heroWidth),
                          height: context.rsV(_WelcomeDesign.heroHeight),
                          child: Image.asset(
                            _WelcomeDesign.heroAsset,
                            // Exact Figma crop positioning (see cropTransform
                            // above); not a generic centered cover.
                            fit: BoxFit.cover,
                            alignment: const Alignment(
                              _WelcomeDesign.heroAlignX,
                              _WelcomeDesign.heroAlignY,
                            ),
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: AppColors.itemSurface,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: context.rs(48),
                                color: AppColors.mediumGray,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Back button (Figma 24,54 44x44, asset button/back).
                    Positioned(
                      left: context.rs(_WelcomeDesign.backButtonX),
                      top: context.rsV(_WelcomeDesign.backButtonY),
                      child: GestureDetector(
                        onTap: () => _onBackPressed(context),
                        behavior: HitTestBehavior.opaque,
                        child: SvgPicture.asset(
                          _WelcomeDesign.backAsset,
                          width: context.rs(_WelcomeDesign.backButtonSize),
                          height: context.rs(_WelcomeDesign.backButtonSize),
                        ),
                      ),
                    ),

                    // Headline (Figma y469, 393 wide, title/large centered).
                    Positioned(
                      top: context.rsV(_WelcomeDesign.titleY),
                      left: 0,
                      right: 0,
                      child: Text(
                        'Welcome to our community with',
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge(
                          context,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),

                    // Signature (Figma x0 y600 393x95, Gardenia 128 #DC2626).
                    Positioned(
                      top: context.rsV(_WelcomeDesign.signatureY),
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        width: context.rs(_WelcomeDesign.signatureWidth),
                        height: context.rsV(_WelcomeDesign.signatureHeight),
                        child: const Center(
                          child: BrandSignatureLogo(
                            designPx: 128,
                            color: _WelcomeDesign.signatureRed,
                          ),
                        ),
                      ),
                    ),

                    // Primary button (Figma 24,754 w345, Style3).
                    Positioned(
                      left: context.rs(_WelcomeDesign.buttonX),
                      top: context.rsV(_WelcomeDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_WelcomeDesign.buttonWidth),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            context.rs(_WelcomeDesign.buttonRadius),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: _WelcomeDesign.buttonBlur,
                              sigmaY: _WelcomeDesign.buttonBlur,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal:
                                    context.rs(_WelcomeDesign.buttonPaddingH),
                                vertical: context.rsV(
                                    _WelcomeDesign.buttonPaddingV),
                              ),
                              decoration: BoxDecoration(
                                color: _WelcomeDesign.buttonBg,
                                borderRadius: BorderRadius.circular(
                                  context.rs(_WelcomeDesign.buttonRadius),
                                ),
                                border: Border.all(
                                  color: _WelcomeDesign.buttonBorder,
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    context.rs(_WelcomeDesign.buttonRadius),
                                  ),
                                  onTap: () => _onGetStartPressed(context),
                                  child: Center(
                                    child: Text(
                                      'Get Start',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.titleMedium(
                                        context,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
