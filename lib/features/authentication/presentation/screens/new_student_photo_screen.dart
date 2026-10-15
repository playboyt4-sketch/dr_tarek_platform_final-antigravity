import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'new_student_grade_screen.dart';

// ---------------------------------------------------------------------------
// Design constants for the "New Student - photo" step (393x852 canvas).
// Raw design-pixel values from Figma dev mode, consumed exclusively via
// context.rs() / context.rsV() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere. Pattern mirrors
// NewStudentWelcomeScreen and NewStudentNameScreen: Scaffold + SafeArea +
// SingleChildScrollView + ConstrainedBox(minHeight: viewportHeight) +
// SizedBox(393x852) + Stack of exact Positioned coordinates.
// ---------------------------------------------------------------------------
abstract final class _PhotoDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Illustration panel: 369x357 at (12, 50), corner radius 35.
  static const illustrationX = 12.0;
  static const illustrationY = 50.0;
  static const illustrationWidth = 369.0;
  static const illustrationHeight = 357.0;
  static const illustrationRadius = 35.0;

  // Floating back button: 44x44 at (24, 64) over the illustration.
  static const backButtonX = 24.0;
  static const backButtonY = 64.0;
  static const backButtonSize = 44.0;

  // Headline frame: 393 wide, 69 tall at y439 ("Add a photo"), centered.
  static const titleY = 439.0;
  static const titleWidth = 393.0;
  static const titleHeight = 69.0;

  // Circular upload target: 159x159 at (117, 534), centered
  // ((393 - 159) / 2 = 117).
  static const uploadX = 117.0;
  static const uploadY = 534.0;
  static const uploadSize = 159.0;

  // Primary CTA: 345 wide at (24, 754), Style = Solid.
  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
  static const buttonHeight = 56.0;
}

class NewStudentPhotoScreen extends StatefulWidget {
  /// Values carried forward from the earlier registration steps, if any.
  /// Pure pass-through — [initialPhotoPath] restores a previously selected
  /// photo (local file path) so going back never loses it. The photo itself
  /// stays optional: `Next` never validates it.
  final String? initialFullName;
  final String? initialPhoneNumber;
  final String? initialPhotoPath;

  const NewStudentPhotoScreen({
    super.key,
    this.initialFullName,
    this.initialPhoneNumber,
    this.initialPhotoPath,
  });

  static const Color backgroundColor = Color(0xFFFFFCF7);
  static const Color primaryBlue = AppColors.buttonSolid;

  @override
  State<NewStudentPhotoScreen> createState() => _NewStudentPhotoScreenState();
}

class _NewStudentPhotoScreenState extends State<NewStudentPhotoScreen> {
  XFile? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Restore a previously selected photo when returning via Back.
    final restored = widget.initialPhotoPath;
    if (restored != null && restored.isNotEmpty) {
      _selectedImage = XFile(restored);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Reuses the existing project image-picker configuration
      // (maxWidth/maxHeight/quality already established on this screen).
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      // Picker cancel: keep current state unchanged, no error, no navigation.
      if (picked != null && mounted) {
        setState(() => _selectedImage = picked);
      }
    } catch (_) {
      // Project-standard presentation: generic SnackBar, never the raw
      // exception (leaks technical internals). Overlay is already closed
      // by the caller; do not crash, do not bypass permissions.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not select a photo. Please try again.'),
            ),
          );
      }
    }
  }

  void _showPhotoPickerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (ctx) => PhotoPickerActionSheet(
        onSourceSelected: (source) {
          Navigator.of(ctx).pop();
          _pickImage(source);
        },
      ),
    );
  }

  void _proceedNext() {
    // Photo is OPTIONAL: navigate with or without a selection.
    // State is preserved via the existing constructor pass-through pattern
    // (same as Full Name / Phone Number); no new global state introduced.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewStudentGradeScreen(
          initialFullName: widget.initialFullName,
          initialPhoneNumber: widget.initialPhoneNumber,
          initialPhotoPath: _selectedImage?.path,
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
    final uploadSize = context.rs(_PhotoDesign.uploadSize);

    return Scaffold(
      backgroundColor: NewStudentPhotoScreen.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR - this is an English-only screen.
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_PhotoDesign.canvasWidth),
                height: context.rsV(_PhotoDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Illustration panel (Figma 12,50 369x357 r35).
                    Positioned(
                      left: context.rs(_PhotoDesign.illustrationX),
                      top: context.rsV(_PhotoDesign.illustrationY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_PhotoDesign.illustrationRadius),
                        ),
                        child: SizedBox(
                          width: context.rs(_PhotoDesign.illustrationWidth),
                          height: context.rsV(
                            _PhotoDesign.illustrationHeight,
                          ),
                          child: Image.asset(
                            // Spec names `New Student - photo.png`,
                            // which is not shipped; reuse the
                            // established photo-step illustration.
                            'assets/images/New Student - add a photo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/new_student photo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF3F4F6),
                                child: const Icon(
                                  Icons.camera_alt_outlined,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- Back button (Figma 24,64 44x44, sibling overlay).
                    Positioned(
                      left: context.rs(_PhotoDesign.backButtonX),
                      top: context.rsV(_PhotoDesign.backButtonY),
                      child: SizedBox(
                        width: context.rs(_PhotoDesign.backButtonSize),
                        height: context.rs(_PhotoDesign.backButtonSize),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 10,
                              sigmaY: 10,
                            ),
                            child: Material(
                              color: Colors.white.withValues(
                                alpha: 0.25,
                              ),
                              shape: CircleBorder(
                                side: BorderSide(
                                  color: Colors.white.withValues(
                                    alpha: 0.35,
                                  ),
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
                                      padding: EdgeInsets.only(
                                        right: 2.0,
                                      ),
                                      child: Icon(
                                        Icons
                                            .arrow_back_ios_new_rounded,
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
                    ),

                    // --- 2. Title (Figma y439, 393x69, centered).
                    Positioned(
                      top: context.rsV(_PhotoDesign.titleY),
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        width: context.rs(_PhotoDesign.titleWidth),
                        height: context.rsV(_PhotoDesign.titleHeight),
                        child: Center(
                          child: Text(
                            'Add a photo',
                            textAlign: TextAlign.center,
                            style: AppTypography.titleLarge(
                              context,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 3. Dashed Circle Upload Target (Figma 117,534
                    // 159x159). Visuals unchanged — only repositioned via
                    // Positioned.
                    Positioned(
                      left: context.rs(_PhotoDesign.uploadX),
                      top: context.rsV(_PhotoDesign.uploadY),
                      child: InkWell(
                        onTap: () => _showPhotoPickerSheet(context),
                        borderRadius: BorderRadius.circular(uploadSize / 2),
                        child: SizedBox(
                          width: uploadSize,
                          height: uploadSize,
                          child: _selectedImage != null
                              ? Stack(
                                  children: [
                                    ClipOval(
                                      child: SizedBox(
                                        width: uploadSize,
                                        height: uploadSize,
                                        child: kIsWeb
                                            ? Image.network(
                                                _selectedImage!.path,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      _,
                                                      __,
                                                      ___,
                                                    ) => Container(
                                                      color: const Color(
                                                        0xFFF3F4F6,
                                                      ),
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported_outlined,
                                                        size: 48,
                                                        color:
                                                            Colors.grey,
                                                      ),
                                                    ),
                                              )
                                            : Image.file(
                                                File(
                                                  _selectedImage!.path,
                                                ),
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      _,
                                                      __,
                                                      ___,
                                                    ) => Container(
                                                      color: const Color(
                                                        0xFFF3F4F6,
                                                      ),
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported_outlined,
                                                        size: 48,
                                                        color:
                                                            Colors.grey,
                                                      ),
                                                    ),
                                              ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: const BoxDecoration(
                                          color: NewStudentPhotoScreen
                                              .primaryBlue,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : CustomPaint(
                                  painter: _DashedCirclePainter(
                                    color: const Color(0xFF9A9A9A),
                                    strokeWidth: 2.0,
                                    dashPattern: const [6, 4],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.add_rounded,
                                      size: 36,
                                      color: NewStudentPhotoScreen
                                          .primaryBlue,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // --- 4. Primary CTA "Next" (Figma 24,754 w345).
                    // Photo is OPTIONAL: never validates, always navigates.
                    Positioned(
                      left: context.rs(_PhotoDesign.buttonX),
                      top: context.rsV(_PhotoDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_PhotoDesign.buttonWidth),
                        height: _PhotoDesign.buttonHeight,
                        child: ElevatedButton(
                          onPressed: _proceedNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                NewStudentPhotoScreen.primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999),
                            ),
                          ),
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

    final radius = size.width / 2 - strokeWidth / 2;
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

/// Frosted-glass photo-source sheet (Figma 393x350, top radius 24).
/// Reuses the existing `showModalBottomSheet` pattern; rows are tappable
/// and dismiss is handled by the caller.
class PhotoPickerActionSheet extends StatelessWidget {
  final Function(ImageSource source) onSourceSelected;

  const PhotoPickerActionSheet({super.key, required this.onSourceSelected});

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
            color: const Color(0x4CFFFCF7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
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
          width: double.infinity,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(icon, size: 24, color: const Color(0xFF111827)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF111827),
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
