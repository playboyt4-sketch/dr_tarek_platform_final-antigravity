import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/session_state.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(authProvider.notifier)
        .login(
          phoneNumber: _phoneController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.hasError || authState.value == null) return;

    ref.invalidate(sessionProvider);
    final session = await ref.read(sessionProvider.future);
    if (!mounted || session is SessionError) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final sessionState = ref.watch(sessionProvider);
    final isLoading = authState.isLoading || sessionState.isLoading;
    final rs = context.rs;

    InputDecoration inputDecoration({
      required String label,
      required String hint,
      Widget? prefixIcon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: EdgeInsets.symmetric(
          horizontal: rs(16),
          vertical: rs(20),
        ),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rs(12)),
          borderSide: const BorderSide(color: Color(0xFFD0D0D0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rs(12)),
          borderSide:
              const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rs(12)),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rs(12)),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Text(
          'Sign In',
          style: TextStyle(
            color: Colors.black,
            fontSize: rs(20),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.pagePadding,
                    vertical: rs(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero image
                      Center(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxHeight: rs(260)),
                          child: Image.asset(
                            'assets/images/current_student.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return SizedBox(
                                height: rs(170),
                                child: Icon(Icons.lock_person_outlined,
                                    size: rs(70),
                                    color: const Color(0xFF2563EB)),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: rs(24)),
                      // Phone Input
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        validator: (value) {
                          final normalized = value?.trim() ?? '';
                          if (normalized.isEmpty) return l10n.errorValidation;
                          if (!RegExp(r'^01[0125]\d{8}$')
                              .hasMatch(normalized)) {
                            return 'يرجى إدخال رقم هاتف مصري صحيح';
                          }
                          return null;
                        },
                        style: TextStyle(fontSize: rs(18)),
                        decoration: inputDecoration(
                          label: 'phone number',
                          hint: 'Enter your phone number',
                          prefixIcon: Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: rs(12)),
                            child: Icon(Icons.smartphone_outlined,
                                color: const Color(0xFF9A9A9A),
                                size: rs(22)),
                          ),
                        ),
                      ),
                      SizedBox(height: rs(16)),
                      // Password Input
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        validator: (value) =>
                            (value == null || value.isEmpty)
                                ? l10n.errorValidation
                                : null,
                        style: TextStyle(fontSize: rs(18)),
                        decoration: inputDecoration(
                          label: 'Password',
                          hint: 'Enter your password',
                          prefixIcon: Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: rs(12)),
                            child: Icon(Icons.lock_outline,
                                color: const Color(0xFF9A9A9A),
                                size: rs(22)),
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: const Color(0xFF9A9A9A),
                              size: rs(22),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: rs(12)),
                      // Forgot password link
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => _showForgotPasswordDialog(context),
                          child: Text(
                            'Forget password?',
                            style: TextStyle(
                              fontSize: rs(14),
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: rs(24)),
                      // Login button
                      SizedBox(
                        height: rs(64),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(rs(12)),
                            ),
                          ),
                          onPressed: isLoading ? null : _login,
                          child: isLoading
                              ? SizedBox(
                                  height: rs(24),
                                  width: rs(24),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: rs(22),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      if (authState.hasError || sessionState.hasError) ...[
                        SizedBox(height: rs(16)),
                        Text(
                          friendlyErrorMessage(
                            context,
                            authState.hasError
                                ? authState.error
                                : sessionState.error,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                            fontSize: rs(14),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }
}
