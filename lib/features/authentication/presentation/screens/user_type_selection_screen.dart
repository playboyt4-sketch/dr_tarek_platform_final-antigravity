import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/design_tokens.dart';
import 'login_screen.dart';
import 'new_student_welcome_screen.dart';
import 'teacher_admin_selection_screen.dart';

/// Design constants — copied from `User_Type_Selection.md`. Spacing/size/
/// font values are raw design-pixels; consumed only via `context.rs()` /
/// `context.rsFont()`. This screen's card area is intentionally flexible
/// (`Expanded`), not fixed-height — see prompt Section 0.
abstract final class _UserTypeSelectionDesign {
  // ---- Page ----
  static const horizontalPadding = 24.0;
  static const topGap = 24.0;

  // ---- Title "I am a" (title/large) ----

  static const titleColor = AppColors.darkText;
  static const titleToSubtitleGap = 8.0;

  // ---- Subtitle (body/regular) ----

  static const subtitleColor = AppColors.mediumGray;
  static const subtitleToCardsGap = 24.0;

  // ---- Cards (shared) ----
  static const cardRadius = 16.0;
  static const cardGap = 16.0;

  static const cardTitleColor = AppColors.canvas;

  // ---- New Student card ----
  static const newStudentBg = AppColors.grade1Canvas; // #F59E0B
  static const newStudentLabel = 'طالب جديد';
  static const newStudentAsset = 'assets/images/new_student.png';

  // ---- Current Student card ----
  static const currentStudentBg = AppColors.grade4Canvas; // #DC2626
  static const currentStudentLabel = 'طالب حالي';
  static const currentStudentAsset = 'assets/images/current_student.png';

  // ---- Footer ----
  static const footerTopGap = 16.0;
  static const signatureFontSize = 128.0; // measured from the transition video — NO
  // shrink vs. Splash; overrides User_Type_Selection.md's incorrect `fontSize: 48`
  static const yearLabel = '2026-2027';

  static const yearColor = AppColors.mediumGray;
  static const yearToIconGap = 8.0;
  static const adminIconSize = 40.0;
  static const bottomGap = 8.0;
}

class UserTypeSelectionScreen extends StatelessWidget {
  const UserTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.rs(_UserTypeSelectionDesign.horizontalPadding),
          ),
          child: Column(
            children: [
              SizedBox(height: context.rs(_UserTypeSelectionDesign.topGap)),
              Text(
                'I am a',
                textAlign: TextAlign.center,
                style: AppTypography.titleLarge(
                  context,
                  color: _UserTypeSelectionDesign.titleColor,
                ),
              ),
              SizedBox(
                height: context.rs(_UserTypeSelectionDesign.titleToSubtitleGap),
              ),
              Text(
                'Select one that applies to you',
                textAlign: TextAlign.center,
                style: AppTypography.bodyRegular(
                  context,
                  color: _UserTypeSelectionDesign.subtitleColor,
                ),
              ),
              SizedBox(
                height: context.rs(_UserTypeSelectionDesign.subtitleToCardsGap),
              ),
              Expanded(
                child: _UserTypeCard(
                  label: _UserTypeSelectionDesign.newStudentLabel,
                  backgroundColor: _UserTypeSelectionDesign.newStudentBg,
                  assetImage: _UserTypeSelectionDesign.newStudentAsset,
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (context, animation, secondaryAnimation) => const NewStudentWelcomeScreen(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: context.rs(_UserTypeSelectionDesign.cardGap)),
              Expanded(
                child: _UserTypeCard(
                  label: _UserTypeSelectionDesign.currentStudentLabel,
                  backgroundColor: _UserTypeSelectionDesign.currentStudentBg,
                  assetImage: _UserTypeSelectionDesign.currentStudentAsset,
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: context.rs(_UserTypeSelectionDesign.footerTopGap)),
              Hero(
                tag: 'brand_logo_signature',
                child: Text(
                  'Tarek el araby',
                  style: AppTypography.signature(
                    context,
                    designPx: _UserTypeSelectionDesign.signatureFontSize,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              Text(
                _UserTypeSelectionDesign.yearLabel,
                style: AppTypography.captionSmall(
                  context,
                  color: _UserTypeSelectionDesign.yearColor,
                ),
              ),
              SizedBox(
                height: context.rs(_UserTypeSelectionDesign.yearToIconGap),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TeacherAdminSelectionScreen(),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(context.rs(4)),
                  child: Image.asset(
                    'assets/images/teacher_admin_icon.png',
                    width: context.rs(_UserTypeSelectionDesign.adminIconSize),
                    height: context.rs(_UserTypeSelectionDesign.adminIconSize),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.person_outline,
                      size: context.rs(_UserTypeSelectionDesign.adminIconSize - 8),
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ),
              SizedBox(height: context.rs(_UserTypeSelectionDesign.bottomGap)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTypeCard extends StatelessWidget {
  const _UserTypeCard({
    required this.label,
    required this.backgroundColor,
    required this.assetImage,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final String assetImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      context.rs(_UserTypeSelectionDesign.cardRadius),
    );

    return ClipRRect(
      borderRadius: radius,
      child: Material(
        color: backgroundColor,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image.asset(
                  assetImage,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomRight,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
              Positioned(
                left: context.rs(20),
                top: context.rs(20),
                child: Text(
                  label,
                  style: AppTypography.titleMedium(
                    context,
                    color: _UserTypeSelectionDesign.cardTitleColor,
                  ).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
