import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'new_student_password_screen.dart';

class NewStudentNumberScreen extends StatefulWidget {
  const NewStudentNumberScreen({super.key});

  static const Color backgroundColor = Colors.white;
  static const Color primaryBlue = Color(0xFF1D4ED8);

  @override
  State<NewStudentNumberScreen> createState() => _NewStudentNumberScreenState();
}

class _NewStudentNumberScreenState extends State<NewStudentNumberScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _validateAndProceed() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رقم الهاتف');
      return;
    }

    final isValidEgyptianPhone = RegExp(r'^01[0125][0-9]{8}$').hasMatch(phone);
    if (!isValidEgyptianPhone) {
      setState(() => _errorMessage = 'يرجى إدخال رقم هاتف مصري صحيح (11 رقم)');
      return;
    }

    setState(() => _errorMessage = null);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewStudentPasswordScreen(),
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
    final illustrationHeight = isCompact ? 240.0 : math.min(screenHeight * 0.42, 355.0);

    return Scaffold(
      backgroundColor: NewStudentNumberScreen.backgroundColor,
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
                                borderRadius: BorderRadius.circular(32),
                                child: Image.asset(
                                  'assets/images/New Student - number photo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/images/New Student - number photo .png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFFF3F4F6),
                                      child: const Icon(Icons.phone_outlined, size: 64, color: Colors.grey),
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

                        const SizedBox(height: 24),

                        // --- 2. Title ---
                        const Text(
                          'Your phone number?',
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

                        // --- 3. Phone Input Field ---
                        SizedBox(
                          width: formWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF111827),
                                ),
                                decoration: InputDecoration(
                                  labelText: 'phone number',
                                  labelStyle: const TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                  hintText: 'Enter your phone number',
                                  hintStyle: const TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: NewStudentNumberScreen.primaryBlue,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontFamily: 'Google Sans Flex',
                                      fontSize: 12,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Spacer maintains the fixed bottom button position across all wizard steps
                        const Spacer(),

                        // --- 4. Pinned Primary Bottom Button ("Next") ---
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0, bottom: 20.0),
                          child: SizedBox(
                            width: formWidth,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _validateAndProceed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NewStudentNumberScreen.primaryBlue,
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
