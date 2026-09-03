import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'new_student_welcome_screen.dart';
import 'student_registration_wizard.dart';

// ---------------------------------------------------------------------------
// Design constants for the "name" step.
// All values are raw design-pixel values from `New Student - name.md`.
// Consumed exclusively via context.rs() / context.rsFont() / context.rsV().
// ---------------------------------------------------------------------------
abstract final class _NameStepDesign {
  // Canvas
  static const canvasWidth  = 393.0;
  static const canvasHeight = 852.0;

  // Hero artwork: 369x344 at (12, 50), corner radius 35
  static const heroX            = 12.0;
  static const heroY            = 50.0;
  static const heroWidth        = 369.0;
  static const heroHeight       = 344.0;
  static const heroCornerRadius = 35.0;
  static const heroAsset = 'assets/images/new_student_name_photo.png';

  // Floating glass back button: 44x44 circle at (24, 64)
  static const backButtonX = 24.0;
  static const backButtonY = 64.0;

  // Title "What is your name?" centred, Y = 426
  static const titleY = 426.0;

  // Input field width 345, height 56, Y = 590
  static const fieldWidth  = 345.0;
  static const fieldHeight = 56.0;
  static const fieldY      = 590.0;

  // Primary "Next" button 345x56, radius full, at (24, 754)
  static const buttonX      = 24.0;
  static const buttonY      = 754.0;
  static const buttonWidth  = 345.0;
  static const buttonHeight = 56.0;
}

// ---------------------------------------------------------------------------
class NewStudentNameScreen extends StatefulWidget {
  const NewStudentNameScreen({super.key});

  @override
  State<NewStudentNameScreen> createState() => _NewStudentNameScreenState();
}

class _NewStudentNameScreenState extends State<NewStudentNameScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Navigation callbacks (logic unchanged) -----------------------------------

  void _onBackPressed() {
    Navigator.of(context).pop(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NewStudentWelcomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    );
  }

  void _onNextPressed() {
    if (_formKey.currentState?.validate() ?? false) {
      final fullName = _nameController.text.trim();
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              StudentRegistrationWizard(
                initialStep: 1,
                initialFullName: fullName,
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            );
          },
        ),
      );
    }
  }

  // Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height
        - MediaQuery.of(context).padding.vertical;

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
                width: context.rs(_NameStepDesign.canvasWidth),
                height: context.rsV(_NameStepDesign.canvasHeight),
                child: Form(
                  key: _formKey,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Hero artwork
                      Positioned(
                        left: context.rs(_NameStepDesign.heroX),
                        top: context.rsV(_NameStepDesign.heroY),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            context.rs(_NameStepDesign.heroCornerRadius),
                          ),
                          child: SizedBox(
                            width: context.rs(_NameStepDesign.heroWidth),
                            height: context.rsV(_NameStepDesign.heroHeight),
                            child: Image.asset(
                              _NameStepDesign.heroAsset,
                              fit: BoxFit.cover,
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

                      // Floating glass back button
                      Positioned(
                        left: context.rs(_NameStepDesign.backButtonX),
                        top: context.rsV(_NameStepDesign.backButtonY),
                        child: _GlassBackButton(onPressed: _onBackPressed),
                      ),

                      // Title: "What's your name?"
                      Positioned(
                        top: context.rsV(_NameStepDesign.titleY),
                        left: 0,
                        right: 0,
                        child: Text(
                          "What's your name?",
                          textAlign: TextAlign.center,
                          style: AppTypography.titleLarge(
                            context,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),

                      // Input field - Full Name
                      Positioned(
                        left: context.rs(
                          (_NameStepDesign.canvasWidth - _NameStepDesign.fieldWidth) / 2,
                        ),
                        top: context.rsV(_NameStepDesign.fieldY),
                        child: SizedBox(
                          width: context.rs(_NameStepDesign.fieldWidth),
                          height: context.rsV(_NameStepDesign.fieldHeight),
                          child: TextFormField(
                            controller: _nameController,
                            style: AppTypography.bodyRegular(
                              context,
                              color: AppColors.darkText,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              hintText: 'Enter your full name',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: context.rs(16),
                                vertical: context.rsV(16),
                              ),
                              labelStyle: AppTypography.bodyRegular(
                                context,
                                color: AppColors.mediumGray,
                              ),
                              hintStyle: AppTypography.bodyRegular(
                                context,
                                color: const Color(0xFF9CA3AF),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  context.rs(AppShapes.radiusMd),
                                ),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  context.rs(AppShapes.radiusMd),
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.buttonSolid,
                                  width: 1.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  context.rs(AppShapes.radiusMd),
                                ),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  context.rs(AppShapes.radiusMd),
                                ),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error,
                                  width: 1.5,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.transparent,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your full name';
                              }
                              if (value.trim().length > 100) {
                                return 'Name must not exceed 100 characters';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),

                      // Primary "Next" button
                      Positioned(
                        left: context.rs(_NameStepDesign.buttonX),
                        top: context.rsV(_NameStepDesign.buttonY),
                        child: SizedBox(
                          width: context.rs(_NameStepDesign.buttonWidth),
                          height: context.rsV(_NameStepDesign.buttonHeight),
                          child: Material(
                            color: AppColors.buttonSolid,
                            borderRadius: BorderRadius.circular(
                              context.rs(AppShapes.radiusFull),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                context.rs(AppShapes.radiusFull),
                              ),
                              onTap: _onNextPressed,
                              child: Center(
                                child: Text(
                                  'Next',
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating glass back button - 44x44 circle, white chevron-left 20 px.
// ---------------------------------------------------------------------------
class _GlassBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GlassBackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.rs(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: context.rs(20), sigmaY: context.rs(20)),
        child: Container(
          width: context.rs(44),
          height: context.rs(44),
          decoration: BoxDecoration(
            color: const Color(0x40FFFFFF),
            borderRadius: BorderRadius.circular(context.rs(22)),
            border: Border.all(
              color: const Color(0x59FFFFFF),
              width: context.rs(1),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(context.rs(22)),
              onTap: onPressed,
              child: Center(
                child: Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: context.rs(20),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
