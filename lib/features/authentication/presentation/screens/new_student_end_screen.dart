import 'dart:math' as math;
import 'package:flutter/material.dart';

class NewStudentEndScreen extends StatelessWidget {
  const NewStudentEndScreen({super.key});

  static const Color backgroundColor = Colors.white;
  static const Color primaryBlue = Color(0xFF1D4ED8);

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
    final illustrationHeight = isCompact ? 220.0 : math.min(screenHeight * 0.40, 348.0);

    return Scaffold(
      backgroundColor: NewStudentEndScreen.backgroundColor,
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

                        // --- 1. Top Illustration (No Back Button per Figma) ---
                        SizedBox(
                          width: contentWidth,
                          height: illustrationHeight,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(35),
                            child: Image.asset(
                              'assets/images/New Student - End photo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                'assets/images/New Student - End photo .png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFF3F4F6),
                                  child: const Icon(Icons.access_time_outlined, size: 64, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- 2. Title ---
                        const Text(
                          'Your request is\nunder review',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // --- 3. Explanation Subtitle ---
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(
                            'We are reviewing your request\nyou will be notified soon',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF6B7280),
                              height: 1.4,
                            ),
                          ),
                        ),

                        // Spacer pushes the button to the fixed bottom anchor
                        const Spacer(),

                        // --- 4. Pinned Primary Bottom Button ("Done") ---
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0, bottom: 20.0),
                          child: SizedBox(
                            width: formWidth,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                // Close registration flow and return to initial gate
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NewStudentEndScreen.primaryBlue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                              ),
                              child: const Text(
                                'Done',
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
