import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
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
        ],
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
