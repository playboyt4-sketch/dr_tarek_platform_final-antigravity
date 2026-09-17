import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/brand_signature_logo.dart';


/// Screen 3.1 — User Type Selection (`I am a` gateway).
///
/// Figma reference frame: 393 x 852, background `#FFFCF7`. All vertical
/// positions below are Figma frame offsets implemented through the
/// project's responsive system ([ResponsiveContext.rs]/[rsV]/[rsFont]):
/// identical to Figma at the reference size, proportionally preserved
/// elsewhere. Design-px constants below are Figma numbers, not invented
/// formulas.
///
/// Frame map (y): title 72 (h~35) → subtitle 115 (h20) → new-student card
/// 145 (345x260, r28) → current-student card 421 (345x260, r28) → logo
/// frame 689 (full-bleed, Hero `brand_logo_signature`, 128 — same size as
/// Splash so the flight interpolates position only) → academic year 767
/// → admin gate 788 (40x40 circle) → bottom margin 24.
///
/// The footer (logo/year/admin) is a fixed-height [Stack] because Figma
/// overlaps them by design (year at logo+78, admin at logo+99). The page
/// scrolls ([ClampingScrollPhysics]) only when OS insets or smaller
/// viewports overflow the reference composition — at 393x852 it rests
/// exactly on the Figma geometry.
class UserTypeSelectionScreen extends StatelessWidget {
  const UserTypeSelectionScreen({super.key});


  @override
  Widget build(BuildContext context) {
    // Figma title top (72) measured from the screen top; the OS status-bar
    // inset is respected without shifting the reference composition.
    final topPad = math.max(
      MediaQuery.paddingOf(context).top,
      context.rsV(72),
    );
    final bottomPad = math.max(
      MediaQuery.paddingOf(context).bottom,
      context.rsV(24),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rs(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Header (Figma y72).
                  Text(
                    'I am a',
                    textAlign: TextAlign.center,
                    style: AppTypography.titleLarge(context),
                  ),
                  SizedBox(height: context.rsV(8)),

                  // Subtitle (Figma y115).
                  Text(
                    'Select one that applies to you',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyRegular(
                      context,
                      color: AppColors.mediumGray,
                    ),
                  ),
                  SizedBox(height: context.rsV(10)),

                  // Card 1: New Student (Figma 24,145 345x260 r28 #F59E0B).
                  _buildCard(
                    context: context,
                    bgColor: const Color(0xFFF59E0B),
                    title: 'طالب جديد',
                    titleColor: const Color(0xFF111827),
                    imagePath: 'assets/images/new_student photo.png',
                    onTap: () =>
                        context.pushNamed(AppRoutes.newStudentWelcome),
                  ),
                  SizedBox(height: context.rsV(16)),

                  // Card 2: Current Student (Figma 24,421 345x260 r28).
                  _buildCard(
                    context: context,
                    bgColor: const Color(0xFFDC2626),
                    title: 'طالب حالي',
                    titleColor: const Color(0xFFFFFCF7),
                    imagePath: 'assets/images/current student photo.png',
                    onTap: () => context.pushNamed(AppRoutes.login),
                  ),
                  SizedBox(height: context.rsV(8)),
                ],
              ),
            ),

            // Footer (logo frame y689; year/admin placed from MEASURED ink
            // geometry, not the 95px nominal frame: the Gardenia 128 line
            // box sits ~9px lower than Figma's tight frame layout (raster
            // probe: app swash reaches +89 in the year column vs Figma +80),
            // so year = 78 + 9 + 1 AA safety, admin keeps Figma's 5px gap
            // to the year bottom. Logo box/position untouched (Hero intact).
            SizedBox(
              width: double.infinity,
              height: context.rsV(149),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Brand signature (Figma x0 y689 w393; Hero destination,
                  // same 128 design size as Splash: position-only flight).
                  const Positioned(
                    top: -24,
                    left: 0,
                    right: 0,
                    child: Hero(
                      tag: 'brand_logo_signature',
                      child: BrandSignatureLogo(designPx: 128),
                    ),
                  ),

                  // Academic year (Figma x4 w393 h16; top clears visible ink).
                  Positioned(
                    top: context.rsV(72),
                    left: 0,
                    right: 0,
                    child: Text(
                      '2026-2027',
                      textAlign: TextAlign.center,
                      style: AppTypography.captionSmall(context),
                    ),
                  ),

                  // Admin gate (Figma x177 40x40; the SVG asset already
                  // contains the 1px #E5E7EB circle, so no extra border).
                  Positioned(
                    top: context.rsV(97),
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => context.pushNamed(
                          AppRoutes.teacherAdminSelection,
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: SvgPicture.asset(
                          'assets/images/teacher & admin icone.svg',
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Figma selection card: 345 wide (capped, centered), 260 tall, r28.
  /// Image composition and navigation behavior are preserved as-is.
  Widget _buildCard({
    required BuildContext context,
    required Color bgColor,
    required String title,
    required Color titleColor,
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 345),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.rs(28)),
          child: Container(
            width: double.infinity,
            height: context.rsV(260),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(context.rs(28)),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
                Positioned(
                  left: context.rs(16),
                  top: context.rsV(24),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.rs(12),
                      vertical: context.rsV(6),
                    ),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.titleMedium(
                        context,
                        color: titleColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
