

import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/widgets/adaptive_layout.dart';
import 'login_screen.dart';
import 'new_student_welcome_screen.dart';
import 'teacher_admin_selection_screen.dart';

class UserTypeSelectionScreen extends StatelessWidget {
  const UserTypeSelectionScreen({super.key});

  static const Color backgroundColor = Color(0xFFFFFCF7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: AdaptiveLayout(
          maxWidth: 800.0,
          mobileBuilder: (context) => _buildScrollableContent(context, false),
          tabletBuilder: (context) => _buildScrollableContent(context, true),
        ),
      ),
    );
  }

  Widget _buildScrollableContent(BuildContext context, bool isTablet) {
    final rsFont = context.rsFont;
    final paddingH = context.rs(24);
    
    // Calculate a max width for the cards so they don't look comically large on tablet
    final double maxCardWidth = isTablet ? 380.0 : double.infinity;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            // Title
            Text(
              'I am a',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: rsFont(36),
                fontWeight: FontWeight.w700, // Inter Bold
                color: const Color(0xFF111827),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            Text(
              'Select one that applies to you',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: rsFont(16),
                fontWeight: FontWeight.w400, // Inter Regular
                color: const Color(0xFF6B7280),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 32),
            
            // Cards Layout
            if (isTablet)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      child: _buildNewStudentCard(context),
                    ),
                  ),
                  SizedBox(width: paddingH),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      child: _buildCurrentStudentCard(context),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildNewStudentCard(context),
                  const SizedBox(height: 32),
                  _buildCurrentStudentCard(context),
                ],
              ),
            
            const SizedBox(height: 32),
            // Platform Logo Hero
            Hero(
              tag: 'brand_logo_signature',
              child: Material(
                color: Colors.transparent,
                child: Text(
                  'Tarek el araby',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Gardenia Summer',
                    fontSize: rsFont(128),
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Teacher/Admin & Academic Year
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const TeacherAdminSelectionScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(rsFont(20)),
                  child: Container(
                    width: rsFont(40),
                    height: rsFont(40),
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/teacher & admin icone.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.person_outline,
                        color: Colors.black,
                        size: rsFont(24),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: context.rs(8)),
                Text(
                  '2026-2027',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: rsFont(10), // Inter Bold, 10px, black
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildNewStudentCard(BuildContext context) {
    return _UserTypeCard(
      cardColor: const Color(0xFFFBCB3D),
      imagePath: 'assets/images/new_student.png',
      title: 'طالب جديد',
      // Illustration Figma relative coords: X=54-24=30, Y=38, W=321, H=241
      imageLeft: 30.0,
      imageTop: 38.0,
      imageWidth: 321.0,
      imageHeight: 241.0,
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (context, animation, secondaryAnimation) =>
                const NewStudentWelcomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                )),
                child: child,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCurrentStudentCard(BuildContext context) {
    return _UserTypeCard(
      cardColor: const Color(0xFFE43639),
      imagePath: 'assets/images/current_student.png',
      title: 'طالب حالي',
      // Illustration Figma relative coords: X=43-24=19, Y=15, W=311, H=260
      imageLeft: 19.0,
      imageTop: 15.0,
      imageWidth: 311.0,
      imageHeight: 260.0,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
    );
  }
}

class _UserTypeCard extends StatelessWidget {
  final Color cardColor;
  final String imagePath;
  final String title;
  final double imageLeft;
  final double imageTop;
  final double imageWidth;
  final double imageHeight;
  final VoidCallback onTap;

  const _UserTypeCard({
    required this.cardColor,
    required this.imagePath,
    required this.title,
    required this.imageLeft,
    required this.imageTop,
    required this.imageWidth,
    required this.imageHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Rigid composition matching Figma 393x260 card aspect
    return AdaptiveAspectContainer(
      designWidth: 345,
      designHeight: 260,
      builder: (context, constraints, scale) {
        return Stack(
          clipBehavior: Clip.none, // DO NOT CLIP the bleeding illustration
          children: [
            // Card Background
            Positioned.fill(
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(28 * scale),
                clipBehavior: Clip.antiAlias, // Clip background only
                child: InkWell(
                  onTap: onTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Arabic label inside card bounds
            Positioned(
              left: 24 * scale,
              top: 24 * scale,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 24 * scale,
                  fontWeight: FontWeight.w700, // Inter Bold
                  color: const Color(0xFFFFFCF7),
                  height: 1.0,
                ),
              ),
            ),
            // Bleeding illustration
            Positioned(
              left: imageLeft * scale,
              top: imageTop * scale,
              width: imageWidth * scale,
              height: imageHeight * scale,
              child: IgnorePointer(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.school_outlined,
                    size: 80 * scale,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
