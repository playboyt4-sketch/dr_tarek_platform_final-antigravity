import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_input.dart';

/// Password recovery per FINAL_DECISIONS Section 3 / 08 Development
/// Standards Section 9: the student submits their registered phone; a
/// `password_reset_requests` document is created server-side via the
/// `submitPasswordResetRequest` callable, which notifies Admin/Teacher.
/// The password is then changed MANUALLY from the Dashboard — there is no
/// automated self-reset and no PIN/verification code of any kind.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();

  bool _sending = false;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'أدخل رقم هاتفك المسجل.');
      return;
    }
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('submitPasswordResetRequest');
      await callable.call(<String, dynamic>{'phoneNumber': phone});
      if (!mounted) return;
      setState(() => _submitted = true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = friendlyFunctionErrorMessage(
            error,
            'تعذر إرسال الطلب. حاول مرة أخرى.',
          ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'تعذر إرسال الطلب. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return const _RequestSubmittedView();
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'أدخل رقم هاتفك المسجل لإرسال طلب استعادة كلمة المرور إلى إدارة المنصة.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            AppInput(
              controller: _phoneController,
              hint: 'رقم الهاتف (01xxxxxxxxx)',
              keyboardType: TextInputType.phone,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: 'إرسال الطلب',
              isLoading: _sending,
              onPressed: _submitRequest,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation view shown after the request is queued: the student waits
/// for Admin/Teacher to change the password from the Dashboard.
class _RequestSubmittedView extends StatelessWidget {
  const _RequestSubmittedView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'تم إرسال طلبك بنجاح',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'وصل طلب استعادة كلمة المرور إلى إدارة المنصة وسيتم مراجعته من '
                  'قِبل الأدمن/المُلّاك. سيتم تغيير كلمة المرور يدويًا من لوحة '
                  'التحكم، ثم يمكنك تسجيل الدخول بكلمة المرور الجديدة. يرجى '
                  'الانتظار والتواصل مع الإدارة إذا استغرق الأمر وقتًا طويلًا.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                AppButton(
                  label: 'رجوع لتسجيل الدخول',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
