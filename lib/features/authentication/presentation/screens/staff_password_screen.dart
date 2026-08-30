import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../domain/entities/session_state.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';

/// Staff sign-in (platform owner + admins): password-only, per the approved
/// Figma frame "teacher and admin - sign in". The staff member picks their
/// name on the selection screen first.
class StaffPasswordScreen extends ConsumerStatefulWidget {
  final String displayName;

  const StaffPasswordScreen({required this.displayName, super.key});

  @override
  ConsumerState<StaffPasswordScreen> createState() =>
      _StaffPasswordScreenState();
}

class _StaffPasswordScreenState extends ConsumerState<StaffPasswordScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(authProvider.notifier)
        .staffLogin(
          displayName: widget.displayName,
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
    final authState = ref.watch(authProvider);
    final sessionState = ref.watch(sessionProvider);
    final isLoading = authState.isLoading || sessionState.isLoading;
    final rs = context.rs;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.displayName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: rs(22),
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: rs(32)),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofocus: true,
                      validator: (value) =>
                          (value == null || value.isEmpty)
                              ? 'يرجى إدخال كلمة المرور'
                              : null,
                      onFieldSubmitted: (_) => isLoading ? null : _login(),
                      style: TextStyle(fontSize: rs(18)),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter your password',
                        prefixIcon: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: rs(12)),
                          child: Icon(Icons.lock_outline,
                              color: const Color(0xFF9A9A9A), size: rs(22)),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() =>
                              _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF9A9A9A),
                            size: rs(22),
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: rs(16),
                          vertical: rs(20),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(rs(12)),
                          borderSide:
                              const BorderSide(color: Color(0xFFD0D0D0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(rs(12)),
                          borderSide: const BorderSide(
                              color: Color(0xFF2563EB), width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(rs(12)),
                          borderSide:
                              const BorderSide(color: Colors.red),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(rs(12)),
                          borderSide: const BorderSide(
                              color: Colors.red, width: 1.5),
                        ),
                      ),
                    ),
                    SizedBox(height: rs(48)),
                    SizedBox(
                      height: rs(64),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(rs(12)),
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
    );
  }
}
