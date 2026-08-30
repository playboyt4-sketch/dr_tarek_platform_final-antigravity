import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/widgets/password_strength_meter.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'يرجى ملء جميع الحقول.');
      return;
    }

    if (newPass.length < 8) {
      setState(() => _errorMessage = 'كلمة المرور الجديدة يجب أن تكون 8 أحرف على الأقل.');
      return;
    }

    final hasUpper = newPass.contains(RegExp(r'[A-Z]'));
    final hasLower = newPass.contains(RegExp(r'[a-z]'));
    final hasDigit = newPass.contains(RegExp(r'[0-9]'));
    final hasSpecial = newPass.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>\-_+=\[\]/\\`~]'));
    if (!hasUpper || !hasLower || !hasDigit || !hasSpecial) {
      setState(() => _errorMessage = 'كلمة المرور يجب أن تحتوي على حرف كبير، حرف صغير، رقم، ورمز خاص.');
      return;
    }

    if (newPass != confirm) {
      setState(() => _errorMessage = 'كلمتا المرور غير متطابقتين.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseFunctions.instance.httpsCallable('changePassword').call({
        'currentPassword': current,
        'newPassword': newPass,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح.')),
      );
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = friendlyFunctionErrorMessage(error, 'فشل تغيير كلمة المرور.'),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = friendlyFunctionErrorMessage(error, 'فشل تغيير كلمة المرور. حاول مرة أخرى.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير كلمة المرور'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            PasswordStrengthMeter(password: _newPasswordController.text),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور الجديدة',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ التغيير'),
        ),
      ],
    );
  }
}
