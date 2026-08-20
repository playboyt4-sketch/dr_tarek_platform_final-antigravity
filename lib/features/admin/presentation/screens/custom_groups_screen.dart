import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';

class CustomGroupsScreen extends StatelessWidget {
  const CustomGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = FirebaseFirestore.instance
        .collection('custom_groups')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('المجموعات المخصصة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: groups,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل المجموعات.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Text(
                'المجموعات المخصصة',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'يمكن للطلاب اختيار المجموعة أثناء التسجيل لتسهيل المراجعة وتعيين المواد.',
              ),
              const SizedBox(height: 20),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد مجموعات مخصصة مسجلة بعد.')),
                )
              else
                ...docs.map((doc) => _GroupCard(group: doc)),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: '+ إضافة مجموعة جديدة',
                icon: Icons.group_add_outlined,
                onPressed: () => _showAddGroupDialog(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddGroupDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إضافة مجموعة مخصصة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم المجموعة (مثال: محاسبين، تدريب)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'الوصف (اختياري)',
                ),
              ),
            ],
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

    final name = nameController.text.trim();
    final description = descController.text.trim();
    nameController.dispose();
    descController.dispose();

    if (confirmed != true || name.isEmpty || !context.mounted) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('createCustomGroup')
          .call({'name': name, 'description': description});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة المجموعة بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت العملية: $error')),
        );
      }
    }
  }
}

class _GroupCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> group;

  const _GroupCard({required this.group});

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _busy = false;

  Future<void> _toggleActive(bool value) async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('updateCustomGroup').call({
        'groupId': widget.group.id,
        'isActive': value,
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر التحديث: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.group.data();
    final name = (data['name'] as String?) ?? widget.group.id;
    final description = (data['description'] as String?) ?? '';
    final isActive = data['is_active'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.groups_outlined, color: AppColors.primary),
        title: Text(name),
        subtitle: description.isEmpty ? null : Text(description),
        trailing: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : CupertinoSwitch(
                value: isActive,
                activeTrackColor: AppColors.primary,
                onChanged: _toggleActive,
              ),
      ),
    );
  }
}
