import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/widgets/password_strength_meter.dart';
import '../providers/forced_password_change_provider.dart';

/// Blocking, non-dismissible, STUDENT-ONLY forced password change UI.
///
/// Approved flow: the student signed in with a temporary password, which IS
/// their current credential. The form therefore collects:
///   1. temporary / current password  -> passed as `currentPassword` to the
///      EXISTING `changePassword` callable (backend requires it),
///   2. new password,
///   3. new password confirmation.
///
/// Blocking guarantees:
/// * [PopScope] with `canPop: false` — no back-button / gesture escape.
/// * No cancel / close / dismiss affordance anywhere in the UI.
/// * [showForcedPasswordChangeDialog] uses `barrierDismissible: false`.
///
/// Success: claims are force-refreshed and the session is
/// invalidated/re-resolved inside [forcedPasswordChangeProvider]; the
/// optional [onCompleted] hook fires (the AuthGate worker uses it to dismiss
/// the dialog / continue routing). No navigation happens here.
/// Failure: the error is shown inline and the user REMAINS in the forced
/// state.
///
/// AuthGate wiring is intentionally left to another worker — this component
/// is only importable/usable:
/// ```dart
/// import 'package:dr_tarek_platform/features/authentication/presentation/widgets/forced_password_change_screen.dart';
///
/// // Full-screen:
/// const ForcedPasswordChangeScreen(onCompleted: ...)
/// // Blocking dialog:
/// await showForcedPasswordChangeDialog(context, onCompleted: ...);
/// ```
class ForcedPasswordChangeScreen extends StatelessWidget {
  /// Called once after a successful forced change (claims refreshed,
  /// session invalidated). Use it to dismiss a wrapping dialog or to let
  /// the session gate re-resolve.
  final VoidCallback? onCompleted;

  /// Greets the signed-in student; purely cosmetic.
  final String? studentName;

  const ForcedPasswordChangeScreen({
    super.key,
    this.onCompleted,
    this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تغيير كلمة المرور مطلوب'),
          // No back button: the screen cannot be escaped.
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _ForcedPasswordChangeForm(
                  studentName: studentName,
                  onCompleted: onCompleted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [_ForcedPasswordChangeForm] as a blocking dialog.
///
/// `barrierDismissible` is false and the route is wrapped in
/// `PopScope(canPop: false)`, so neither tapping outside nor the back
/// button can dismiss it. The dialog pops itself (with `true`) only after
/// a successful change; on failure it stays open. Returns the dialog result
/// (`true` on success, `null` if the route was removed by other means).
Future<bool?> showForcedPasswordChangeDialog(
  BuildContext context, {
  VoidCallback? onCompleted,
  String? studentName,
}) {
  return showDialog<bool>(
    context: context,
    // Blocking: tapping the barrier must NOT dismiss.
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      // Blocking: the back button must NOT dismiss.
      canPop: false,
      child: Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _ForcedPasswordChangeForm(
              studentName: studentName,
              onCompleted: () {
                Navigator.of(dialogContext).pop(true);
                onCompleted?.call();
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shared forced-change form used by both [ForcedPasswordChangeScreen] and
/// [showForcedPasswordChangeDialog].
///
/// Validation rules intentionally mirror
/// `lib/features/profile/presentation/widgets/change_password_dialog.dart`
/// (existing dialog): required fields, new password >= 8 chars with
/// upper + lower + digit + special, and confirmation match. Strength
/// feedback reuses the shared [PasswordStrengthMeter] design-system widget.
class _ForcedPasswordChangeForm extends ConsumerStatefulWidget {
  final VoidCallback? onCompleted;
  final String? studentName;

  const _ForcedPasswordChangeForm({this.onCompleted, this.studentName});

  @override
  ConsumerState<_ForcedPasswordChangeForm> createState() =>
      _ForcedPasswordChangeFormState();
}

class _ForcedPasswordChangeFormState
    extends ConsumerState<_ForcedPasswordChangeForm> {
  final _temporaryPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureTemporary = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _validationError;

  static final _specialCharsRegex = RegExp(
    r'[!@#$%^&*(),.?":{}|<>\-_+=\[\]/\\`~]',
  );

  @override
  void dispose() {
    _temporaryPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Local validation mirroring ChangePasswordDialog. Returns `true` when
  /// the input is submittable; otherwise shows the message inline and
  /// returns `false` (the user stays in the forced state).
  bool _validate() {
    final current = _temporaryPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      setState(() => _validationError = 'يرجى ملء جميع الحقول.');
      return false;
    }

    if (newPass.length < 8) {
      setState(
        () => _validationError =
            'كلمة المرور الجديدة يجب أن تكون 8 أحرف على الأقل.',
      );
      return false;
    }

    final hasUpper = newPass.contains(RegExp(r'[A-Z]'));
    final hasLower = newPass.contains(RegExp(r'[a-z]'));
    final hasDigit = newPass.contains(RegExp(r'[0-9]'));
    final hasSpecial = newPass.contains(_specialCharsRegex);
    if (!hasUpper || !hasLower || !hasDigit || !hasSpecial) {
      setState(
        () => _validationError =
            'كلمة المرور يجب أن تحتوي على حرف كبير، حرف صغير، رقم، ورمز خاص.',
      );
      return false;
    }

    if (newPass != confirm) {
      setState(() => _validationError = 'كلمتا المرور غير متطابقتين.');
      return false;
    }

    setState(() => _validationError = null);
    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    await ref
        .read(forcedPasswordChangeProvider.notifier)
        .submit(
          // The temporary password IS the current credential.
          currentPassword: _temporaryPasswordController.text,
          newPassword: _newPasswordController.text,
        );
    // Success/failure side effects are handled in the ref.listen below:
    // success -> snackbar + onCompleted; failure -> inline error, remain
    // in the forced state.
  }

  @override
  Widget build(BuildContext context) {
    final changeState = ref.watch(forcedPasswordChangeProvider);
    final loading = changeState.isLoading;

    // Success: notify once (claims refreshed + session re-resolving).
    // Failure: surface the mapped message inline and STAY forced.
    ref.listen<AsyncValue<bool>>(forcedPasswordChangeProvider, (_, next) {
      if (!mounted) return;
      if (next.hasValue && (next.value ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم تغيير كلمة المرور بنجاح. سجل الدخول بالباسورد الجديدة.',
            ),
          ),
        );
        widget.onCompleted?.call();
      } else if (next.hasError) {
        setState(
          () => _validationError = friendlyFunctionErrorMessage(
            next.error,
            'فشل تغيير كلمة المرور. حاول مرة أخرى.',
          ),
        );
      }
    });

    final backendError = changeState.hasError
        ? friendlyFunctionErrorMessage(
            changeState.error,
            'فشل تغيير كلمة المرور. حاول مرة أخرى.',
          )
        : null;
    final errorMessage = _validationError ?? backendError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset_outlined, size: 48),
        const SizedBox(height: 12),
        const Text(
          'تغيير كلمة المرور مطلوب',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          widget.studentName != null && widget.studentName!.isNotEmpty
              ? 'مرحباً ${widget.studentName}، حسابك يستخدم كلمة مرور مؤقتة. '
                    'أدخل كلمة المرور المؤقتة ثم اختر كلمة مرور جديدة قوية للمتابعة.'
              : 'حسابك يستخدم كلمة مرور مؤقتة. '
                    'أدخل كلمة المرور المؤقتة ثم اختر كلمة مرور جديدة قوية للمتابعة. '
                    'لا يمكنك استخدام التطبيق قبل إتمام هذه الخطوة.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _temporaryPasswordController,
          obscureText: _obscureTemporary,
          enabled: !loading,
          decoration: InputDecoration(
            labelText: 'كلمة المرور المؤقتة (الحالية)',
            helperText: 'كلمة المرور المؤقتة التي سجلت الدخول بها',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureTemporary = !_obscureTemporary),
              icon: Icon(
                _obscureTemporary
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNew,
          enabled: !loading,
          onChanged: (_) {
            setState(() {});
            if (_validationError != null) {
              setState(() => _validationError = null);
            }
          },
          decoration: InputDecoration(
            labelText: 'كلمة المرور الجديدة',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
              icon: Icon(
                _obscureNew
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        PasswordStrengthMeter(password: _newPasswordController.text),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          enabled: !loading,
          decoration: InputDecoration(
            labelText: 'تأكيد كلمة المرور الجديدة',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            errorMessage,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          // Single action, no cancel: the flow is mandatory.
          onPressed: loading ? null : _submit,
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('حفظ ومتابعة'),
        ),
      ],
    );
  }
}
