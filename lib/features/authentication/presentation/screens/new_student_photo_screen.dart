import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'new_student_grade_screen.dart';

class NewStudentPhotoScreen extends StatefulWidget {
  const NewStudentPhotoScreen({super.key});

  static const Color backgroundColor = Colors.white;
  static const Color primaryBlue = Color(0xFF1D4ED8);

  @override
  State<NewStudentPhotoScreen> createState() => _NewStudentPhotoScreenState();
}

class _NewStudentPhotoScreenState extends State<NewStudentPhotoScreen> {
  XFile? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _selectedImage = picked);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _showPhotoPickerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black.withOpacity(0.40),
      builder: (ctx) => PhotoPickerActionSheet(
        onSourceSelected: (source) {
          Navigator.of(ctx).pop();
          _pickImage(source);
        },
      ),
    );
  }

  void _proceedNext() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewStudentGradeScreen(),
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
    final illustrationHeight = isCompact ? 230.0 : math.min(screenHeight * 0.42, 357.0);

    return Scaffold(
      backgroundColor: NewStudentPhotoScreen.backgroundColor,
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
                                  'assets/images/New Student - add a photo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: const Color(0xFFF3F4F6),
                                    child: const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
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

                        const SizedBox(height: 20),

                        // --- 2. Title ---
                        const Text(
                          'Add a photo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- 3. Dotted Circle Upload Target (159x159 px) ---
                        Center(
                          child: InkWell(
                            onTap: () => _showPhotoPickerSheet(context),
                            borderRadius: BorderRadius.circular(80),
                            child: SizedBox(
                              width: 159,
                              height: 159,
                              child: _selectedImage != null
                                  ? Stack(
                                      children: [
                                        ClipOval(
                                          child: SizedBox(
                                            width: 159,
                                            height: 159,
                                            child: kIsWeb
                                                ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                                                : Image.file(File(_selectedImage!.path), fit: BoxFit.cover),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: const BoxDecoration(
                                              color: NewStudentPhotoScreen.primaryBlue,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.edit, size: 18, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    )
                                  : CustomPaint(
                                      painter: _DashedCirclePainter(
                                        color: const Color(0xFFD1D5DB),
                                        strokeWidth: 1.5,
                                        dashPattern: const [6, 4],
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 36,
                                          color: NewStudentPhotoScreen.primaryBlue,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        // Spacer pushes the button to the fixed bottom anchor
                        const Spacer(),

                        // --- 4. Pinned Primary Bottom Button ("Next") ---
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0, bottom: 20.0),
                          child: SizedBox(
                            width: formWidth,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _proceedNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NewStudentPhotoScreen.primaryBlue,
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

/// Custom painter to draw a true circular dashed border
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final List<double> dashPattern;

  _DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashPattern,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * math.pi * radius;

    final dashLength = dashPattern[0];
    final gapLength = dashPattern.length > 1 ? dashPattern[1] : dashPattern[0];
    final totalDashLength = dashLength + gapLength;
    final count = (circumference / totalDashLength).floor();
    final sweepAngle = (2 * math.pi * (dashLength / totalDashLength)) / count;
    final gapAngle = (2 * math.pi * (gapLength / totalDashLength)) / count;

    double currentAngle = 0.0;
    for (int i = 0; i < count; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        currentAngle,
        sweepAngle,
        false,
        paint,
      );
      currentAngle += sweepAngle + gapAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}

/// Frosted Glass Action Sheet matching Figma `modal/photo-picker` 1:1
class PhotoPickerActionSheet extends StatelessWidget {
  final Function(ImageSource source) onSourceSelected;

  const PhotoPickerActionSheet({
    super.key,
    required this.onSourceSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: double.infinity,
          height: 350,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.80),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.40)),
          ),
          child: Column(
            children: [
              // Top Drag Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              const SizedBox(height: 28),
              // Option 1: Take a photo
              _buildOptionTile(
                icon: Icons.camera_alt_outlined,
                title: 'Take a photo',
                onTap: () => onSourceSelected(ImageSource.camera),
              ),
              const SizedBox(height: 16),
              // Option 2: Choose from gallery
              _buildOptionTile(
                icon: Icons.photo_library_outlined,
                title: 'Choose from gallery',
                onTap: () => onSourceSelected(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: const Color(0xFF111827)),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
