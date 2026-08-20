import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/session_state.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/auth_password_field.dart';
import '../widgets/auth_phone_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
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
    final authState = ref.watch(authProvider);
    final sessionState = ref.watch(sessionProvider);
    final isLoading = authState.isLoading || sessionState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthPhoneField(controller: _phoneController),
            const SizedBox(height: 16),
            AuthPasswordField(controller: _passwordController),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _login,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(),
                    )
                  : const Text('Login'),
            ),
            if (authState.hasError || sessionState.hasError) ...[
              const SizedBox(height: 16),
              Text(
                (authState.hasError ? authState.error : sessionState.error)
                    .toString()
                    .replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
