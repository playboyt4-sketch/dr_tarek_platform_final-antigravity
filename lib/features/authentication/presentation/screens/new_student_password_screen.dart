import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../profile/data/services/pending_profile_photo_store.dart';
import '../providers/auth_provider.dart';
import '../providers/registration_form_provider.dart';
import 'new_student_end_screen.dart';

// ---------------------------------------------------------------------------
// Design constants for the "New Student - password" step (Figma 393x852).
// Raw design-pixel values from Figma dev mode, consumed exclusively via
// context.rs() / context.rsV() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere. Pattern mirrors
// NewStudentWelcomeScreen and NewStudentNameScreen (sibling steps):
// Scaffold + SafeArea + SingleChildScrollView + ConstrainedBox(minHeight:
// viewportHeight) + Directionality LTR + SizedBox(393x852) + Stack of exact
// Positioned coordinates.
// ---------------------------------------------------------------------------
abstract final class _PasswordDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Illustration panel: 369x325 at (12, 50), corner radius 35.
  static const illustrationX = 12.0;
  static const illustrationY = 50.0;
  static const illustrationWidth = 369.0;
  static const illustrationHeight = 325.0;
  static const illustrationRadius = 35.0;
  static const illustrationAsset =
      'assets/images/New Student - password photo.png';

  // Floating back button: 44x44 at (24, 64) over the illustration.
  // Sibling Positioned on the page Stack (same as Welcome/Name), pops.
  static const backButtonX = 24.0;
  static const backButtonY = 64.0;
  static const backButtonSize = 44.0;

  // Title frame: 374x68 at (10, 407), centered.
  static const titleX = 10.0;
  static const titleY = 407.0;
  static const titleWidth = 374.0;
  static const titleHeight = 68.0;

  // Password field 1 ("Enter password"): 345 wide at (24, 501.5), radius 16.
  static const fieldX = 24.0;
  static const fieldWidth = 345.0;
  static const field1Y = 501.5;

  // Helper text: 356x31 at (24, 584), centered.
  static const helperX = 24.0;
  static const helperY = 584.0;
  static const helperWidth = 356.0;
  static const helperHeight = 31.0;

  // Password field 2 ("Re-Enter password"): 345 wide at (24, 630),
  // radius 16, eye toggle.
  static const field2Y = 630.0;

  // Validation message: NOT in Figma — slots into the gap between field 2
  // (bottom ~686) and the CTA (top 754) so error logic stays identical
  // without covering any Figma-positioned element.
  static const errorY = 692.0;

  // Primary CTA ("Next"): 345 wide at (24, 754), 56 tall.
  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
  static const buttonHeight = 56.0;
}

class NewStudentPasswordScreen extends ConsumerStatefulWidget {
  /// Pass-through registration state from earlier steps (same pattern as
  /// Full Name / Phone Number / Photo / Grade). Pure carry-forward so going
  /// back never loses the Grade selection; no new global state introduced.
  final String? initialFullName;
  final String? initialPhoneNumber;
  final String? initialPhotoPath;
  final String? initialGrade;

  const NewStudentPasswordScreen({
    super.key,
    this.initialFullName,
    this.initialPhoneNumber,
    this.initialPhotoPath,
    this.initialGrade,
  });

  static const Color backgroundColor = Colors.white;
  static const Color primaryBlue = Color(0xFF1D4ED8);

  @override
  ConsumerState<NewStudentPasswordScreen> createState() =>
      _NewStudentPasswordScreenState();
}

class _NewStudentPasswordScreenState
    extends ConsumerState<NewStudentPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  /// True while the `registerNewStudent` callable is in flight — the CTA
  /// shows a spinner and ignores extra taps (no double submission).
  bool _submitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Final registration step: local password validation first, then the
  /// REAL backend submission (`registerNewStudent` → `users/{uid}` with
  /// `role: new_student`, `approval_status: pending`), which is exactly
  /// what the dashboard Pending Requests screen lists. On success the
  /// draft is cleared and the End ("under review") screen is pushed; on a
  /// server error (e.g. phone already registered) the friendly Arabic
  /// message stays on this screen — no navigation, no raw exceptions.
  Future<void> _validateAndSubmit() async {
    if (_submitting) return;
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كلمة المرور وتأكيدها');
      return;
    }

    if (password.length < 8) {
      setState(
        () => _errorMessage = 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل',
      );
      return;
    }

    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
    if (!hasDigit || !hasLetter) {
      setState(
        () => _errorMessage = 'كلمة المرور يجب أن تحتوي على أحرف وأرقام',
      );
      return;
    }

    if (password != confirm) {
      setState(() => _errorMessage = 'كلمتا المرور غير متطابقتين');
      return;
    }

    // Gather the earlier steps: explicit constructor carry-forward wins,
    // otherwise the shared draft (Name/Number wrote it; Photo/Grade only
    // travel via constructors — the draft has no setters for them yet).
    final draft = ref.read(registrationFormProvider);
    final fullName = widget.initialFullName ?? draft.fullName;
    final phoneNumber = widget.initialPhoneNumber ?? draft.phoneNumber;
    final profilePhoto = widget.initialPhotoPath ?? draft.profilePhotoPath;
    final grade = widget.initialGrade ?? draft.grade;
    if (fullName.trim().isEmpty ||
        phoneNumber.trim().isEmpty ||
        grade == null ||
        grade.isEmpty) {
      setState(
        () => _errorMessage =
            'بيانات التسجيل غير مكتملة، ارجع وأكمل الخطوات السابقة.',
      );
      return;
    }

    setState(() {
      _errorMessage = null;
      _submitting = true;
    });
    // The photo step only produces a LOCAL device path, which is useless as
    // a profile URL (and must never be stored in `users.profile_photo`).
    // Stash it for upload on first login — registration runs signed-out, so
    // Storage/Firestore are not writable yet. The backend receives null.
    // Web has no local filesystem for the pending stash (`File` throws
    // UnsupportedError there), so the stash is skipped on web and the
    // photo is simply not carried forward.
    if (!kIsWeb && profilePhoto != null && profilePhoto.trim().isNotEmpty) {
      await PendingProfilePhotoStore.savePath(
        phone: phoneNumber.trim(),
        path: profilePhoto,
      );
    }
    await ref.read(authProvider.notifier).register(
          fullName: fullName.trim(),
          phoneNumber: phoneNumber.trim(),
          profilePhoto: null,
          grade: grade,
          password: password,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    final authState = ref.read(authProvider);
    if (authState.hasError) {
      // Server-side failure (duplicate phone, no internet, …) — friendly
      // Arabic copy only, never the raw exception.
      setState(
        () => _errorMessage = friendlyErrorMessage(context, authState.error),
      );
      return;
    }

    // Submission accepted: clear the in-memory draft (it also holds the
    // password) and show the "under review" confirmation.
    ref.read(registrationFormProvider.notifier).reset();
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NewStudentEndScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // Same viewport math as the Welcome/Name screens: the fixed 393x852
    // Stack lives INSIDE the SafeArea, so Figma's y-coords (measured from
    // the canvas top) land correctly without any manual top/bottom padding
    // to tune.
    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;
    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      backgroundColor: semantic.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR — same as the Welcome/Name sibling steps.
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_PasswordDesign.canvasWidth),
                height: context.rsV(_PasswordDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Illustration panel (Figma 12,50 369x325 r35).
                    // BoxFit.cover crops cleanly to the box — never
                    // BoxFit.fill, which stretches the art.
                    Positioned(
                      left: context.rs(_PasswordDesign.illustrationX),
                      top: context.rsV(_PasswordDesign.illustrationY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_PasswordDesign.illustrationRadius),
                        ),
                        child: SizedBox(
                          key: const Key('passwordIllustrationStack'),
                          width:
                              context.rs(_PasswordDesign.illustrationWidth),
                          height: context.rsV(
                              _PasswordDesign.illustrationHeight),
                          child: Image.asset(
                            _PasswordDesign.illustrationAsset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: semantic.surface,
                              child: Icon(
                                Icons.shield_outlined,
                                size: 64,
                                color: semantic.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- Back button (Figma 24,64 44x44, sibling overlay).
                    // Same glass markup as before — only hoisted out of the
                    // illustration box into a sibling Positioned (Welcome/
                    // Name pattern). Still pops the route.
                    Positioned(
                      left: context.rs(_PasswordDesign.backButtonX),
                      top: context.rsV(_PasswordDesign.backButtonY),
                      child: SizedBox(
                        width:
                            context.rs(_PasswordDesign.backButtonSize),
                        height:
                            context.rs(_PasswordDesign.backButtonSize),
                        child: ClipOval(
                          child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: 10,
                            sigmaY: 10,
                          ),
                          child: Material(
                            color: semantic.glassBackFill,
                            shape: CircleBorder(
                              side: BorderSide(
                                color: semantic.glassBackBorder,
                                width: 1.0,
                              ),
                            ),
                            child: InkWell(
                              onTap: () =>
                                  Navigator.of(context).pop(),
                              customBorder: const CircleBorder(),
                              child: SizedBox(
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
                                      color: semantic.glassText,
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

                    // --- 2. Title (Figma 10,407 374x68, centered).
                    Positioned(
                      left: context.rs(_PasswordDesign.titleX),
                      top: context.rsV(_PasswordDesign.titleY),
                      child: SizedBox(
                        width: context.rs(_PasswordDesign.titleWidth),
                        height:
                            context.rsV(_PasswordDesign.titleHeight),
                        child: Center(
                          child: Text(
                            'Secure your account',
                            key: const Key('passwordTitle'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: semantic.textPrimary,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 3a. Password field 1 (Figma 24,501.5 w345, r16).
                    // Eye toggle included like field 2 (Teacher request —
                    // Figma shows it only on the confirm field).
                    Positioned(
                      left: context.rs(_PasswordDesign.fieldX),
                      top: context.rsV(_PasswordDesign.field1Y),
                      child: SizedBox(
                        width: context.rs(_PasswordDesign.fieldWidth),
                        child: TextField(
                          key: const Key('passwordField1'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                          },
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: semantic.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter password',
                            hintStyle: TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 14,
                              color: semantic.textTertiary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: semantic.textSecondary,
                                size: 22,
                              ),
                              onPressed: _toggleObscurePassword,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: semantic.inputBorderSubtle,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: semantic.inputBorderSubtle,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: semantic.inputBorderFocused,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 3b. Helper (Figma 24,584 356x31, centered).
                    Positioned(
                      left: context.rs(_PasswordDesign.helperX),
                      top: context.rsV(_PasswordDesign.helperY),
                      child: SizedBox(
                        width: context.rs(_PasswordDesign.helperWidth),
                        height:
                            context.rsV(_PasswordDesign.helperHeight),
                        child: Center(
                          child: Text(
                            'كلمة المرور يجب أن تحتوي على 8 أحرف ورقم على الأقل',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 13,
                              fontWeight: FontWeight.w100,
                              color: semantic.textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 3c. Password field 2 (Figma 24,630 w345, r16).
                    // With eye toggle icon per Figma. Decoration kept as-is.
                    Positioned(
                      left: context.rs(_PasswordDesign.fieldX),
                      top: context.rsV(_PasswordDesign.field2Y),
                      child: SizedBox(
                        width: context.rs(_PasswordDesign.fieldWidth),
                        child: TextField(
                          key: const Key('passwordField2'),
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                          },
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: semantic.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Re-Enter password',
                            hintStyle: TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 14,
                              color: semantic.textTertiary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: semantic.textSecondary,
                                size: 22,
                              ),
                              onPressed: _toggleObscureConfirm,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: semantic.inputBorderSubtle,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: semantic.inputBorderSubtle,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: semantic.inputBorderFocused,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 3d. Validation message (gap slot 692, not Figma).
                    if (_errorMessage != null)
                      Positioned(
                        left: context.rs(_PasswordDesign.fieldX),
                        top: context.rsV(_PasswordDesign.errorY),
                        child: SizedBox(
                          width:
                              context.rs(_PasswordDesign.fieldWidth),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 12,
                              color: semantic.isDark
                                  ? semantic.error
                                  : Colors.redAccent,
                            ),
                          ),
                        ),
                      ),

                    // --- 4. Primary CTA (Figma 24,754 w345).
                    // Submits the registration to the backend; spinner
                    // while the callable is in flight, disabled against
                    // double taps.
                    Positioned(
                      left: context.rs(_PasswordDesign.buttonX),
                      top: context.rsV(_PasswordDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_PasswordDesign.buttonWidth),
                        height: _PasswordDesign.buttonHeight,
                        child: ElevatedButton(
                          onPressed:
                              _submitting ? null : _validateAndSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: semantic.primary,
                            foregroundColor: semantic.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999),
                            ),
                          ),
                          child: _submitting
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: semantic.onPrimary,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
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
          ),
        ),
      ),
    );
  }

  void _toggleObscurePassword() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _toggleObscureConfirm() {
    setState(() => _obscureConfirm = !_obscureConfirm);
  }
}
