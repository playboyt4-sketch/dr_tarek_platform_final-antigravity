import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'new_student_end_screen.dart';

enum AcademicGrade {
  grade1('Grade one', '1', Color(0xFFF59E0B)),
  grade2('Grade two', '2', Color(0xFF1D4ED8)),
  grade3('Grade three', '3', Color(0xFF15803D)),
  grade4('Grade four', '4', Color(0xFFDC2626));

  final String label;
  final String number;
  final Color color;

  const AcademicGrade(this.label, this.number, this.color);
}

class NewStudentGradeScreen extends StatefulWidget {
  const NewStudentGradeScreen({super.key});

  static const Color backgroundColor = Colors.white;
  static const Color primaryBlue = Color(0xFF1D4ED8);

  @override
  State<NewStudentGradeScreen> createState() => _NewStudentGradeScreenState();
}

class _NewStudentGradeScreenState extends State<NewStudentGradeScreen> {
  AcademicGrade _selectedGrade = AcademicGrade.grade1;

  void _proceedNext() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewStudentEndScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    final topPadding = math.max(mediaQuery.padding.top, 20.0);
    final bottomPadding = math.max(mediaQuery.padding.bottom, 16.0);

    final contentWidth = math.min(screenWidth - 24.0, 369.0);
    final formWidth = math.min(screenWidth - 48.0, 345.0);

    final isCompact = screenHeight < 740.0;
    final illustrationHeight = isCompact ? 200.0 : math.min(screenHeight * 0.36, 324.0);

    return Scaffold(
      backgroundColor: NewStudentGradeScreen.backgroundColor,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        // --- 1. Top Illustration with Floating Glass Back Button ---
                        SizedBox(
                          width: contentWidth,
                          height: illustrationHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(35),
                                child: Image.asset(
                                  'assets/images/New Student - Grade photo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/images/New Student - grade.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFFF3F4F6),
                                      child: const Icon(Icons.school_outlined, size: 64, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),

                              // Floating Glass Back Button
                              Positioned(
                                top: 16,
                                left: 16,
                                child: ClipOval(
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                    child: Material(
                                      color: Colors.white.withOpacity(0.25),
                                      shape: CircleBorder(
                                        side: BorderSide(
                                          color: Colors.white.withOpacity(0.35),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: InkWell(
                                        onTap: () => Navigator.of(context).pop(),
                                        customBorder: const CircleBorder(),
                                        child: const SizedBox(
                                          width: 44,
                                          height: 44,
                                          child: Center(
                                            child: Padding(
                                              padding: EdgeInsets.only(right: 2.0),
                                              child: Icon(
                                                Icons.arrow_back_ios_new_rounded,
                                                color: Colors.white,
                                                size: 18,
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

                        const SizedBox(height: 18),

                        // --- 2. Title ---
                        const Text(
                          'Which year are you in?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // --- 3. 4 Selectable Grade Capsules ---
                        SizedBox(
                          width: formWidth,
                          child: Column(
                            children: AcademicGrade.values.map((grade) {
                              final isSelected = _selectedGrade == grade;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10.0),
                                child: _GradeCapsuleTile(
                                  grade: grade,
                                  isSelected: isSelected,
                                  onTap: () => setState(() => _selectedGrade = grade),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Spacer pushes the button to the fixed bottom anchor
                        const Spacer(),

                        // --- 4. Pinned Primary Bottom Button ("Next") ---
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                          child: SizedBox(
                            width: formWidth,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _proceedNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NewStudentGradeScreen.primaryBlue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                              ),
                              child: const Text(
                                'Next',
                                style: TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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
      ),
    );
  }
}

class _GradeCapsuleTile extends StatelessWidget {
  final AcademicGrade grade;
  final bool isSelected;
  final VoidCallback onTap;

  const _GradeCapsuleTile({
    required this.grade,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      decoration: BoxDecoration(
        color: grade.color,
        borderRadius: BorderRadius.circular(9999),
        border: isSelected ? Border.all(color: Colors.white, width: 3.0) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                  grade.label,
                  style: const TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    grade.number,
                    style: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
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
