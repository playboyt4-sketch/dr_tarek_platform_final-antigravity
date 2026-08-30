import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../authentication/domain/entities/auth_user.dart';

/// Admin management screen.
///
/// Teacher (Platform Owner) only: add/remove admins and toggle each
/// delegated permission with a [CupertinoSwitch]. Permission keys match
/// `activeAdminPermission` in firestore.rules exactly.
class AdminsManagementScreen extends StatelessWidget {
  final AuthUser user;

  const AdminsManagementScreen({required this.user, super.key});

  static const permissionKeys = <({String key, String label})>[
    (key: 'admin_students', label: 'إدارة الطلاب'),
    (key: 'password_reset', label: 'إعادة تعيين كلمة المرور'),
    (key: 'admin_devices', label: 'إدارة وتغيير الأجهزة'),
    (key: 'admin_content', label: 'إدارة المحتوى والمحاضرات'),
    (key: 'admin_academic_terms', label: 'إدارة الفترات الدراسية'),
    (key: 'admin_payments_view', label: 'عرض المدفوعات'),
    (key: 'admin_payments', label: 'تسجيل وتحصيل المدفوعات'),
    (key: 'admin_analytics', label: 'عرض التحليلات'),
    (key: 'admin_settings', label: 'إعدادات النظام'),
  ];

  @override
  Widget build(BuildContext context) {
    if (user.role != 'teacher') {
      return const Scaffold(
        body: Center(child: Text('إدارة الأدمنز متاحة للمعلم (مالك المنصة) فقط.')),
      );
    }

    final admins = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأدمنز')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: admins,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل قائمة الأدمنز.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا يوجد أدمنز بعد.')),
                )
              else
                ...docs.map((doc) => _AdminCard(admin: doc)),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: '+ إضافة أدمن',
                icon: Icons.person_add_alt_outlined,
                onPressed: () => _showAddAdminDialog(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddAdminDialog(BuildContext context) async {
    final idController = TextEditingController();
    final selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('إضافة أدمن جديد'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'معرّف المستخدم (UID)',
                        hintText: 'معرّف حساب موجود في المنصة',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('الصلاحيات المفوّضة'),
                    const SizedBox(height: 4),
                    for (final permission in permissionKeys)
                      Row(
                        children: [
                          Expanded(child: Text(permission.label)),
                          CupertinoSwitch(
                            value: selected.contains(permission.key),
                            activeTrackColor: AppColors.primary,
                            onChanged: (value) => setState(() {
                              value
                                  ? selected.add(permission.key)
                                  : selected.remove(permission.key);
                            }),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );

    final userId = idController.text.trim();
    idController.dispose();

    if (confirmed != true || userId.isEmpty || !context.mounted) return;

    try {
      await FirebaseFunctions.instance.httpsCallable('addAdmin').call({
        'userId': userId,
        'permissions': {for (final key in selected) key: true},
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة الأدمن بنجاح.')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر إضافة الأدمن.'))),
        );
      }
    }
  }
}

class _AdminCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> admin;

  const _AdminCard({required this.admin});

  @override
  State<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<_AdminCard> {
  final _pending = <String>{};
  bool _removing = false;

  Future<void> _togglePermission(String key, bool value, Map<String, bool> current) async {
    setState(() => _pending.add(key));
    try {
      await FirebaseFunctions.instance.httpsCallable('setAdminPermissions').call({
        'userId': widget.admin.id,
        'permissions': {...current, key: value},
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر تحديث الصلاحية.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(key));
    }
  }

  Future<void> _removeAdmin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الأدمن؟'),
        content: const Text('سيتم سحب كل الصلاحيات المفوّضة وتعطيل الحساب الإداري.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('removeAdmin')
          .call({'userId': widget.admin.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الأدمن.')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر حذف الأدمن.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.admin.data();
    final name = (data['full_name'] as String?) ?? widget.admin.id;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('admin_permissions')
            .doc(widget.admin.id)
            .snapshots(),
        builder: (context, snapshot) {
          final permissionsData = snapshot.data?.data();
          final raw = permissionsData?['permissions'];
          final current = <String, bool>{
            for (final permission in AdminsManagementScreen.permissionKeys)
              permission.key:
                  raw is Map && raw[permission.key] == true,
          };
          final isActive = permissionsData?['is_active'] == true;

          return ExpansionTile(
            leading: Icon(
              Icons.admin_panel_settings_outlined,
              color: isActive ? AppColors.primary : AppColors.muted,
            ),
            title: Text(name),
            subtitle: Text(isActive ? 'أدمن نشط' : 'صلاحيات غير مفعّلة'),
            children: [
              for (final permission in AdminsManagementScreen.permissionKeys)
                ListTile(
                  dense: true,
                  title: Text(permission.label),
                  trailing: _pending.contains(permission.key)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : CupertinoSwitch(
                          value: current[permission.key] ?? false,
                          activeTrackColor: AppColors.primary,
                          onChanged: (value) =>
                              _togglePermission(permission.key, value, current),
                        ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: OutlinedButton.icon(
                  onPressed: _removing ? null : _removeAdmin,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: Text(_removing ? 'جارٍ الحذف...' : 'حذف الأدمن'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
