import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../domain/entities/delete_account_result.dart';
import '../providers/profile_providers.dart';

/// Student profile — photo upload flows through [ProfileRepository]; the
/// widget contains no Firebase/storage code.
class StudentProfileScreen extends ConsumerStatefulWidget {
  final AuthUser user;
  const StudentProfileScreen({required this.user, super.key});

  @override
  ConsumerState<StudentProfileScreen> createState() =>
      _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  bool uploading = false;

  Future<void> _pickAndUploadPhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (image == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await image.readAsBytes();
      final repo = ref.read(profileRepositoryProvider);
      final url = await repo.uploadProfilePhoto(
        userId: uid,
        bytes: bytes,
        fileName: '${DateTime.now().millisecondsSinceEpoch}_avatar.jpg',
      );
      await repo.updateProfilePhotoUrl(userId: uid, url: url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث صورة الملف الشخصي.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر رفع الصورة، حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final l10n = AppLocalizations.of(context);
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isLoading = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.deleteAccountDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.deleteAccountDialogWarning,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                Text(l10n.deleteAccountDialogDescription),
                const SizedBox(height: 24),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n.deleteAccountPasswordLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setDialogState(() =>
                          obscurePassword = !obscurePassword),
                    ),
                  ),
                  enabled: !isLoading,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: isLoading || passwordController.text.isEmpty
                  ? null
                  : () async {
                      setDialogState(() {
                        isLoading = true;
                        errorMessage = null;
                      });
                      final result = await ref
                          .read(deleteMyAccountUseCaseProvider)
                          .execute(password: passwordController.text);
                      if (!ctx.mounted) return;
                      if (result is DeleteAccountResult) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(l10n.deleteAccountSuccessMessage)),
                          );
                          await ref.read(authProvider.notifier).logout();
                        }
                      } else {
                        // Handle failure
                        final failure = result as Failure;
                        String friendlyMessage;
                        if (failure.code == FailureCode.wrongCredentials) {
                          friendlyMessage = l10n.errorWrongCredentials;
                        } else if (failure.code == FailureCode.tooManyRequests) {
                          // Use backend message if it contains lock duration
                          friendlyMessage =
                              failure.debugDetail?.contains('minute') == true
                                  ? failure.debugDetail!
                                  : l10n.errorTooManyRequests;
                        } else if (failure.code == FailureCode.permissionDenied) {
                          friendlyMessage = l10n.errorPermissionDenied;
                        } else if (failure.code == FailureCode.wrongCredentials &&
                            failure.debugDetail?.contains('Invalid password') ==
                                true) {
                          friendlyMessage = l10n.errorWrongCredentials;
                        } else {
                          friendlyMessage = l10n.errorGeneric;
                        }
                        setDialogState(() {
                          isLoading = false;
                          errorMessage = friendlyMessage;
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(l10n.deleteAccountConfirmButton),
            ),
          ],
        ),
      ),
    );
  }

  bool _showDangerZone(AuthUser user) {
    return user.role == 'student' || user.role == 'new_student';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(title: const Text('ملفي الشخصي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: user.profilePhoto == null
                      ? null
                      : NetworkImage(user.profilePhoto!),
                  child: user.profilePhoto == null
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
                IconButton.filled(
                  tooltip: 'تغيير الصورة',
                  onPressed: uploading ? null : _pickAndUploadPhoto,
                  icon: uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _ProfileRow(label: 'الاسم', value: user.fullName),
          _ProfileRow(label: 'رقم الهاتف', value: user.phoneNumber),
          _ProfileRow(label: 'الفرقة', value: user.grade ?? 'غير محددة'),
          _ProfileRow(label: 'حالة الحساب', value: user.accountStatus),
          const SizedBox(height: 24),
          AppButton(
            label: 'تسجيل الخروج',
            icon: Icons.logout,
            variant: AppButtonVariant.outlined,
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
          if (_showDangerZone(user)) ...[
            const SizedBox(height: 32),
            _DangerZoneCard(onDeletePressed: _showDeleteAccountDialog),
          ],
        ],
      ),
    );
  }
}

class _DangerZoneCard extends StatelessWidget {
  final VoidCallback onDeletePressed;
  const _DangerZoneCard({required this.onDeletePressed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: colorScheme.error, size: 24),
                const SizedBox(width: 8),
                Text(
                  l10n.dangerZoneTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.dangerZoneDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.delete_forever_outlined,
                    color: colorScheme.error),
                label: Text(
                  l10n.dangerZoneDeleteButton,
                  style: TextStyle(color: colorScheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colorScheme.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: onDeletePressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(label), trailing: Text(value));
  }
}