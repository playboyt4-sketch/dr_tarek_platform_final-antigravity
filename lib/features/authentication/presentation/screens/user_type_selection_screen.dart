import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
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
class UserTypeSelectionScreen extends StatefulWidget {
  const UserTypeSelectionScreen({super.key});

  @override
  State<UserTypeSelectionScreen> createState() =>
      _UserTypeSelectionScreenState();
}

class _UserTypeSelectionScreenState extends State<UserTypeSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        unawaited(preloadSubjectsAndCovers(container, context));
      } catch (_) {
        // Standalone widget tests without ProviderScope skip preloading cleanly.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppSemanticColors.of(context).canvasWarm,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final cardHeight = ((availableHeight - context.rsV(220)) / 2)
                .clamp(145.0, context.rsV(230));

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: availableHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rs(24),
                    vertical: context.rsV(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Header (Figma y72).
                      Text(
                        'I am a',
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge(context),
                      ),
                      SizedBox(height: context.rsV(6)),

                      // Subtitle (Figma y115).
                      Text(
                        'Select one that applies to you',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyRegular(
                          context,
                          color:
                              AppSemanticColors.of(context).textSecondary,
                        ),
                      ),
                      SizedBox(height: context.rsV(12)),

                      // Card 1: New Student (Figma 24,145 345x260 r28 #F59E0B).
                      _buildCard(
                        context: context,
                        bgColor: const Color(0xFFF59E0B),
                        title: 'طالب جديد',
                        titleColor: const Color(0xFF111827),
                        imagePath: 'assets/images/new_student photo.png',
                        cardHeight: cardHeight,
                        onTap: () async {
                          if (FirebaseAuth.instance.currentUser != null) {
                            try {
                              await FirebaseAuth.instance.signOut();
                            } catch (_) {}
                          }
                          if (context.mounted) {
                            context.pushNamed(AppRoutes.newStudentWelcome);
                          }
                        },
                      ),
                      SizedBox(height: context.rsV(14)),

                      // Card 2: Current Student (Figma 24,421 345x260 r28).
                      _buildCard(
                        context: context,
                        bgColor: const Color(0xFFDC2626),
                        title: 'طالب حالي',
                        titleColor: const Color(0xFFFFFCF7),
                        imagePath:
                            'assets/images/current student photo.png',
                        cardHeight: cardHeight,
                        onTap: () => context.pushNamed(AppRoutes.login),
                      ),
                      SizedBox(height: context.rsV(24)),

                      // Footer (logo frame y689; year/admin placed from MEASURED ink
                      SizedBox(
                        width: double.infinity,
                        height: context.rsV(120),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned(
                              top: -20,
                              left: 0,
                              right: 0,
                              child: Hero(
                                tag: 'brand_logo_signature',
                                child: BrandSignatureLogo(designPx: 128),
                              ),
                            ),
                            Positioned(
                              top: context.rsV(60),
                              left: 0,
                              right: 0,
                              child: Text(
                                '2026-2027',
                                textAlign: TextAlign.center,
                                style: AppTypography.captionSmall(context),
                              ),
                            ),
                            Positioned(
                              top: context.rsV(80),
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
                                    width: 38,
                                    height: 38,
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
              ),
            );
          },
        ),
      ),
    );
  }

  /// Figma selection card: 345 wide (capped, centered), responsive cardHeight, r28.
  Widget _buildCard({
    required BuildContext context,
    required Color bgColor,
    required String title,
    required Color titleColor,
    required String imagePath,
    required double cardHeight,
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
            height: cardHeight,
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
