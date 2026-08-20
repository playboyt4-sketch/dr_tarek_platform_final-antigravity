// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'new_student_welcome_screen.dart';
import 'teacher_admin_selection_screen.dart';

class UserTypeSelectionScreen extends StatelessWidget {
  const UserTypeSelectionScreen({super.key});

  // ===============================================================
  // DESIGN REFERENCE
  // Figma reference canvas: 393 × 852
  // These values are design geometry, NOT screen scaling factors.
  // ===============================================================

  static const double designWidth = 393;
  static const double designHeight = 852;

  static const Color backgroundColor = Color(0xFFFFFCF7);

  // ===============================================================
  // SCREEN GEOMETRY
  // ===============================================================

  static const _ScreenGeometry geometry = _ScreenGeometry(
    title: _ElementGeometry(x: 0, y: 62, width: 393, height: 36),
    subtitle: _ElementGeometry(x: 0, y: 107, width: 393, height: 16),
    newStudentCard: _ElementGeometry(x: 24, y: 145, width: 345, height: 260),
    currentStudentCard: _ElementGeometry(
      x: 24,
      y: 418,
      width: 345,
      height: 260,
    ),
    platformLogo: _ElementGeometry(x: 0, y: 678, width: 393, height: 100),
    academicYear: _ElementGeometry(x: 221, y: 787, width: 100, height: 16),
    teacherAdminIcon: _ElementGeometry(x: 180, y: 803, width: 34, height: 34),
  );

  // ===============================================================
  // CARD GEOMETRY
  // ===============================================================

  static const _CardGeometry newStudentCard = _CardGeometry(
    card: _ElementGeometry(x: 24, y: 145, width: 345, height: 260),
    image: _ElementGeometry(x: 0, y: 0, width: 369, height: 260),
    title: _ElementGeometry(x: 22, y: 40, width: 128, height: 48),
  );

  static const _CardGeometry currentStudentCard = _CardGeometry(
    card: _ElementGeometry(x: 24, y: 418, width: 345, height: 260),
    image: _ElementGeometry(x: 0, y: 0, width: 369, height: 278),
    title: _ElementGeometry(x: 22, y: 36, width: 128, height: 48),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;

            // =======================================================
            // ADAPTIVE CONTENT WIDTH
            //
            // 393 is the reference width.
            //
            // On larger screens:
            //   content remains 393 wide and is centered.
            //
            // On smaller screens:
            //   content uses the available width.
            //
            // There is NO proportional scaling.
            // =======================================================

            final contentWidth = screenWidth < designWidth
                ? screenWidth
                : designWidth;

            final contentLeft = (screenWidth - contentWidth) / 2;

            // =======================================================
            // VERTICAL CONTENT
            //
            // The design geometry remains intact.
            // If the viewport is shorter than the design,
            // SingleChildScrollView allows natural scrolling.
            // =======================================================

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: screenWidth,
                height: designHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // =================================================
                    // BACKGROUND
                    // =================================================
                    const Positioned.fill(
                      child: ColoredBox(color: backgroundColor),
                    ),

                    // =================================================
                    // TITLE
                    // =================================================
                    Positioned(
                      left: contentLeft,
                      top: geometry.title.y,
                      child: SizedBox(
                        width: contentWidth,
                        height: geometry.title.height,
                        child: const Text(
                          'I am a',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),

                    // =================================================
                    // SUBTITLE
                    // =================================================
                    Positioned(
                      left: contentLeft,
                      top: geometry.subtitle.y,
                      child: SizedBox(
                        width: contentWidth,
                        height: geometry.subtitle.height,
                        child: const Text(
                          'Select one that applies to you',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),

                    // =================================================
                    // NEW STUDENT CARD
                    // =================================================
                    Positioned(
                      left:
                          contentLeft +
                          _centeredOffset(
                            geometry.newStudentCard,
                            contentWidth,
                          ),
                      top: geometry.newStudentCard.y,
                      child: _UserTypeCard(
                        cardGeometry: newStudentCard,
                        cardColor: const Color(0xFFFBCB3D),
                        imagePath: 'assets/images/new_student.png',
                        title: 'New Student',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NewStudentWelcomeScreen(),
                            ),
                          );
                        },
                      ),
                    ),

                    // =================================================
                    // CURRENT STUDENT CARD
                    // =================================================
                    Positioned(
                      left:
                          contentLeft +
                          _centeredOffset(
                            geometry.currentStudentCard,
                            contentWidth,
                          ),
                      top: geometry.currentStudentCard.y,
                      child: _UserTypeCard(
                        cardGeometry: currentStudentCard,
                        cardColor: const Color(0xFFE43639),
                        imagePath: 'assets/images/current_student.png',
                        title: 'Current Student',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                      ),
                    ),

                    // =================================================
                    // PLATFORM LOGO
                    // =================================================
                    Positioned(
                      left: contentLeft,
                      top: geometry.platformLogo.y,
                      child: SizedBox(
                        width: contentWidth,
                        height: geometry.platformLogo.height,
                        child: const Hero(
                          tag: 'splash-logo',
                          child: Material(
                            color: Colors.transparent,
                            child: Text(
                              'Tarek el araby',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Gardenia Summer',
                                fontSize: 128,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // =================================================
                    // ACADEMIC YEAR
                    // =================================================
                    Positioned(
                      left: contentLeft + geometry.academicYear.x,
                      top: geometry.academicYear.y,
                      child: const SizedBox(
                        width: 100,
                        height: 16,
                        child: Text(
                          '2026-2027',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),

                    // =================================================
                    // TEACHER / ADMIN ICON
                    // =================================================
                    Positioned(
                      left: contentLeft + geometry.teacherAdminIcon.x,
                      top: geometry.teacherAdminIcon.y,
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const TeacherAdminSelectionScreen(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.person_outline,
                            color: Colors.black,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ===============================================================
  // CENTER ELEMENT INSIDE THE DESIGN WIDTH
  // ===============================================================

  static double _centeredOffset(_ElementGeometry element, double contentWidth) {
    return (contentWidth - element.width) / 2;
  }
}

// ===================================================================
// SCREEN GEOMETRY
// ===================================================================

class _ScreenGeometry {
  final _ElementGeometry title;
  final _ElementGeometry subtitle;
  final _ElementGeometry newStudentCard;
  final _ElementGeometry currentStudentCard;
  final _ElementGeometry platformLogo;
  final _ElementGeometry academicYear;
  final _ElementGeometry teacherAdminIcon;

  const _ScreenGeometry({
    required this.title,
    required this.subtitle,
    required this.newStudentCard,
    required this.currentStudentCard,
    required this.platformLogo,
    required this.academicYear,
    required this.teacherAdminIcon,
  });
}

// ===================================================================
// ELEMENT GEOMETRY
// ===================================================================

class _ElementGeometry {
  final double x;
  final double y;
  final double width;
  final double height;

  const _ElementGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

// ===================================================================
// CARD GEOMETRY
// ===================================================================

class _CardGeometry {
  final _ElementGeometry card;
  final _ElementGeometry image;
  final _ElementGeometry title;

  const _CardGeometry({
    required this.card,
    required this.image,
    required this.title,
  });
}

// ===================================================================
// USER TYPE CARD
// ===================================================================

class _UserTypeCard extends StatelessWidget {
  final _CardGeometry cardGeometry;

  final Color cardColor;
  final String imagePath;
  final String title;
  final VoidCallback onTap;

  const _UserTypeCard({
    required this.cardGeometry,
    required this.cardColor,
    required this.imagePath,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = cardGeometry.card;
    final image = cardGeometry.image;
    final titleGeometry = cardGeometry.title;

    return SizedBox(
      width: card.width,
      height: card.height,
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // =====================================================
              // IMAGE
              // =====================================================
              Positioned(
                left: image.x,
                top: image.y,
                child: SizedBox(
                  width: image.width,
                  height: image.height,
                  child: Image.asset(imagePath, fit: BoxFit.fill),
                ),
              ),

              // =====================================================
              // TITLE
              // =====================================================
              Positioned(
                left: titleGeometry.x,
                top: titleGeometry.y,
                child: SizedBox(
                  width: titleGeometry.width,
                  height: titleGeometry.height,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFFCF7),
                      height: 1.0,
                    ),
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
