import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../admin/domain/admin_grades.dart';
import 'new_student_password_screen.dart';

/// Presentation details for one grade row.
///
/// The **valid grade set** comes from [kCanonicalGradeKeys] (existing domain
/// configuration). This class only holds Figma display data (English label,
/// numeric badge, row color from existing [AppColors] grade tokens) keyed by
/// the canonical persisted value (`grade_one` … `grade_four`).
class _GradeOption {
  final String key;
  final String label;
  final String number;
  final Color color;

  const _GradeOption({
    required this.key,
    required this.label,
    required this.number,
    required this.color,
  });
}

/// Figma display mapping for the current four grades. Keys are taken from
/// [kCanonicalGradeKeys] so the widget never hardcodes the valid grade set;
/// only presentation (label/badge/color) lives here.
List<_GradeOption> _gradeOptions() {
  const display = <String, Map<String, Object>>{
    'grade_one': {'label': 'Grade one', 'number': '1'},
    'grade_two': {'label': 'Grade two', 'number': '2'},
    'grade_three': {'label': 'Grade three', 'number': '3'},
    'grade_four': {'label': 'Grade four', 'number': '4'},
  };
  const colors = <String, Color>{
    'grade_one': AppColors.grade1Canvas,
    'grade_two': AppColors.grade2Canvas,
    'grade_three': AppColors.grade3Canvas,
    'grade_four': AppColors.grade4Canvas,
  };
  return [
    for (final key in kCanonicalGradeKeys)
      _GradeOption(
        key: key,
        label: display[key]!['label']! as String,
        number: display[key]!['number']! as String,
        color: colors[key]!,
      ),
  ];
}

// ---------------------------------------------------------------------------
// Design constants for the "New Student - Grade" step (393x852 canvas).
// Raw design-pixel values from Figma, consumed exclusively via
// context.rs() / context.rsV() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere. Pattern mirrors
// NewStudentWelcomeScreen and NewStudentNameScreen: Scaffold + SafeArea +
// SingleChildScrollView + ConstrainedBox(minHeight: viewportHeight) +
// SizedBox(393x852) + Stack of exact Positioned coordinates.
//
// Geometry reference (Figma raw export, 393x852 canvas):
// illustration 369x324 @ (12,50) radius 35, back button 44 @ (24,64) as a
// sibling overlay on the page Stack, title 393 wide @ y406 (frame h69,
// centered), grades list 345 wide @ (24,466) — 4 capsules each 345x60
// radius 9999 with a 12px vertical gap. There is NO bottom CTA: tapping a
// capsule selects it and pushes the Password step immediately
// (Teacher request — deliberate Figma deviation).
//
// The simulated OS status bar in the Figma export is NOT reproduced — the
// OS draws the real status bar and [SafeArea] already insets for it.
// ---------------------------------------------------------------------------
abstract final class _GradeDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Illustration panel: 369x324 at (12, 50), corner radius 35.
  static const illustrationX = 12.0;
  static const illustrationY = 50.0;
  static const illustrationWidth = 369.0;
  static const illustrationHeight = 324.0;
  static const illustrationRadius = 35.0;

  // Floating back button: 44x44 at (24, 64) over the illustration.
  static const backButtonX = 24.0;
  static const backButtonY = 64.0;
  static const backButtonSize = 44.0;

  // Headline frame: 393 wide at y406 ("Which year are you in?"), h69.
  static const titleY = 406.0;

  // Grades list: 345 wide at (24, 466); 4 capsules 345x60 r9999, gap 12.
// NOTE (Teacher request): there is NO bottom CTA on this screen — tapping
// a capsule selects that grade AND navigates forward immediately.
  static const listX = 24.0;
  static const listY = 466.0;
  static const listWidth = 345.0;
  static const capsuleHeight = 60.0;
  static const capsuleGap = 12.0;
}

class NewStudentGradeScreen extends StatefulWidget {
  /// Pass-through registration state from earlier steps (same pattern as
  /// Full Name / Phone Number / Photo). [initialGrade] holds the previously
  /// selected persisted value (`grade_one` …), if any — null means nothing
  /// selected yet. There is intentionally NO `grade_one` business default:
  /// Figma showing Grade one first is visual order only.
  final String? initialFullName;
  final String? initialPhoneNumber;
  final String? initialPhotoPath;
  final String? initialGrade;

  const NewStudentGradeScreen({
    super.key,
    this.initialFullName,
    this.initialPhoneNumber,
    this.initialPhotoPath,
    this.initialGrade,
  });

  static const Color backgroundColor = Color(0xFFFFFCF7);

  @override
  State<NewStudentGradeScreen> createState() => _NewStudentGradeScreenState();
}

class _NewStudentGradeScreenState extends State<NewStudentGradeScreen> {
  /// Persisted grade key (`grade_one` …) or null when nothing selected.
  /// Initialized ONLY from the existing registration state — never
  /// defaulted to `grade_one`.
  String? _selectedGradeKey;

  @override
  void initState() {
    super.initState();
    // Restore a previously selected grade when returning via Back.
    // normalizeAdminGradeKey keeps validation in the existing domain layer.
    _selectedGradeKey = normalizeAdminGradeKey(widget.initialGrade);
  }

  /// Teacher request: no "Next" button on this screen — tapping a capsule
  /// selects that grade and navigates to the Password step immediately.
  /// The tapped key always comes from [_gradeOptions] (itself keyed by
  /// [kCanonicalGradeKeys]), so no separate validation/error state is
  /// needed: a tap IS a valid selection.
  void _selectGradeAndProceed(String gradeKey) {
    setState(() => _selectedGradeKey = gradeKey);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewStudentPasswordScreen(
          initialFullName: widget.initialFullName,
          initialPhoneNumber: widget.initialPhoneNumber,
          initialPhotoPath: widget.initialPhotoPath,
          initialGrade: gradeKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same viewport math as the Welcome/Name screens: the fixed 393x852
    // Stack lives INSIDE the SafeArea, so Figma's y-coords (measured from
    // the canvas top, status-bar chrome included) land correctly without
    // any manual top/bottom padding to tune.
    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;

    final options = _gradeOptions();
    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      backgroundColor: semantic.canvasWarm,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR - this is an English-only screen.
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_GradeDesign.canvasWidth),
                height: context.rsV(_GradeDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Illustration panel (Figma 12,50 369x324 r35).
                    // BoxFit.cover crops cleanly to the box — never
                    // BoxFit.fill, which stretches the art.
                    Positioned(
                      left: context.rs(_GradeDesign.illustrationX),
                      top: context.rsV(_GradeDesign.illustrationY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_GradeDesign.illustrationRadius),
                        ),
                        child: SizedBox(
                          key: const Key('gradeIllustration'),
                          width: context.rs(_GradeDesign.illustrationWidth),
                          height: context
                              .rsV(_GradeDesign.illustrationHeight),
                          child: Image.asset(
                            'assets/images/New Student - Grade photo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: semantic.surface,
                              child: Icon(
                                Icons.school_outlined,
                                size: 64,
                                color: semantic.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- Back button (Figma 24,64 44x44, sibling overlay).
                    // Sibling Positioned on the page Stack — NOT a child of
                    // the illustration box (same pattern as Welcome/Name).
                    Positioned(
                      left: context.rs(_GradeDesign.backButtonX),
                      top: context.rsV(_GradeDesign.backButtonY),
                      child: SizedBox(
                        width: context.rs(_GradeDesign.backButtonSize),
                        height: context.rs(_GradeDesign.backButtonSize),
                        child: const _GradeBackButton(),
                      ),
                    ),

                    // --- 2. Headline (Figma y406, 393 wide, centered).
                    Positioned(
                      top: context.rsV(_GradeDesign.titleY),
                      left: 0,
                      right: 0,
                      child: Text(
                        'Which year are you in?',
                        key: const Key('gradeTitle'),
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge(
                          context,
                          color: semantic.textPrimary,
                        ),
                      ),
                    ),

                    // --- 3. Selectable grade capsules (Figma 24,466 w345).
                    // 4 capsules 345x60 r9999, 12px vertical gap. Tapping
                    // a capsule selects it AND navigates forward at once
                    // (no bottom CTA — Teacher request).
                    Positioned(
                      left: context.rs(_GradeDesign.listX),
                      top: context.rsV(_GradeDesign.listY),
                      child: SizedBox(
                        key: const Key('gradeList'),
                        width: context.rs(_GradeDesign.listWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < options.length; i++) ...[
                              _GradeCapsuleTile(
                                option: options[i],
                                isSelected:
                                    _selectedGradeKey == options[i].key,
                                onTap: () => _selectGradeAndProceed(
                                  options[i].key,
                                ),
                              ),
                              if (i < options.length - 1)
                                SizedBox(
                                  height: context
                                      .rsV(_GradeDesign.capsuleGap),
                                ),
                            ],
                          ],
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

/// Thin adapter so the overlay back button can be `const` inside the page
/// `Stack` while keeping the pop behavior identical. Visuals match the
/// previous floating glass button exactly (white 25% fill, white 35% 1px
/// stroke, blur 10, white `arrow_back_ios_new_rounded` chevron 18px).
class _GradeBackButton extends StatelessWidget {
  const _GradeBackButton();

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: semantic.glassBackFill,
          shape: CircleBorder(
            side: BorderSide(
              color: semantic.glassBackBorder,
              width: 1.0,
            ),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).pop(),
            customBorder: const CircleBorder(),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 2.0),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: semantic.glassText,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradeCapsuleTile extends StatelessWidget {
  final _GradeOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _GradeCapsuleTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    // Light keeps the approved saturated capsule + white text. Dark follows
    // ADR-009 D3 Option B: neutral surfaceContainer fill with the grade
    // accent carried by the border + number badge, and the approved grade
    // text tint on top.
    final accent = switch (option.key) {
      'grade_one' => semantic.gradeAccent1,
      'grade_two' => semantic.gradeAccent2,
      'grade_three' => semantic.gradeAccent3,
      'grade_four' => semantic.gradeAccent4,
      _ => semantic.gradeAccent1,
    };
    final gradeText = switch (option.key) {
      'grade_one' => semantic.gradeText1,
      'grade_two' => semantic.gradeText2,
      'grade_three' => semantic.gradeText3,
      'grade_four' => semantic.gradeText4,
      _ => semantic.gradeText1,
    };
    final capsuleFill = semantic.isDark
        ? semantic.surfaceContainer
        : option.color;
    final textColor = semantic.isDark ? gradeText : Colors.white;
    final Border? border = semantic.isDark
        ? Border.all(color: accent, width: isSelected ? 3.0 : 1.0)
        : (isSelected ? Border.all(color: Colors.white, width: 3.0) : null);
    final badgeFill = semantic.isDark
        ? accent
        : Colors.white.withValues(alpha: 0.25);
    final badgeBorder = semantic.isDark
        ? null
        : Border.all(
            color: Colors.white.withValues(alpha: 0.30),
            width: 1.0,
          );
    final badgeTextColor = semantic.isDark
        ? semantic.onInverseSurface
        : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: context.rsV(_GradeDesign.capsuleHeight),
      decoration: BoxDecoration(
        color: capsuleFill,
        borderRadius: BorderRadius.circular(9999),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  option.label,
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: badgeFill,
                    shape: BoxShape.circle,
                    border: badgeBorder,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    option.number,
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: badgeTextColor,
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
