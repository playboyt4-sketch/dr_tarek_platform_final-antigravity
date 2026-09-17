import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'new_student_end_screen.dart';

class NewStudentPasswordScreen extends StatefulWidget {
  const NewStudentPasswordScreen({super.key});

  static const Color backgroundColor = Colors.white;
  static const Color primaryBlue = Color(0xFF1D4ED8);

  @override
  State<NewStudentPasswordScreen> createState() => _NewStudentPasswordScreenState();
}

class _NewStudentPasswordScreenState extends State<NewStudentPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscureConfirm = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _validateAndProceed() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كلمة المرور وتأكيدها');
      return;
    }

    if (password.length < 8) {
      setState(() => _errorMessage = 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل');
      return;
    }

    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
    if (!hasDigit || !hasLetter) {
      setState(() => _errorMessage = 'كلمة المرور يجب أن تحتوي على أحرف وأرقام');
      return;
    }

    if (password != confirm) {
      setState(() => _errorMessage = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() => _errorMessage = null);

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
    final illustrationHeight = isCompact ? 210.0 : math.min(screenHeight * 0.38, 325.0);

    return Scaffold(
      backgroundColor: NewStudentPasswordScreen.backgroundColor,
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
                                  'assets/images/New Student - password photo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: const Color(0xFFF3F4F6),
                                    child: const Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
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
                          'Secure your account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 18),

                        // --- 3. Password Input Fields & Policy ---
                        SizedBox(
                          width: formWidth,
                          child: Column(
                            children: [
                              // Field 1: Enter password (no toggle icon per Figma)
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                onChanged: (_) {
                                  if (_errorMessage != null) setState(() => _errorMessage = null);
                                },
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF111827),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter password',
                                  hintStyle: const TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                                    borderSide: const BorderSide(color: NewStudentPasswordScreen.primaryBlue, width: 1.5),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Password Policy Helper (Thin style per Figma)
                              const Text(
                                'كلمة المرور يجب أن تحتوي على 8 أحرف ورقم على الأقل',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w100,
                                  color: Color(0xFF6B7280),
                                  height: 1.2,
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Field 2: Re-Enter password (with eye toggle icon per Figma)
                              TextField(
                                controller: _confirmController,
                                obscureText: _obscureConfirm,
                                onChanged: (_) {
                                  if (_errorMessage != null) setState(() => _errorMessage = null);
                                },
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF111827),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Re-Enter password',
                                  hintStyle: const TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: const Color(0xFF6B7280),
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      setState(() => _obscureConfirm = !_obscureConfirm);
                                    },
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                                    borderSide: const BorderSide(color: NewStudentPasswordScreen.primaryBlue, width: 1.5),
                                  ),
                                ),
                              ),

                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontFamily: 'Google Sans Flex',
                                    fontSize: 12,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ],
                            ],
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
                              onPressed: _validateAndProceed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NewStudentPasswordScreen.primaryBlue,
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
