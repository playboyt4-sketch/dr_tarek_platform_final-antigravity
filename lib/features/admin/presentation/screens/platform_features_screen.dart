import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../authentication/domain/entities/auth_user.dart';

/// Platform-wide feature matrix.
///
/// Toggles apply to the whole platform (not a specific plan) through the
/// `platform_features` collection - same pattern as plan_features
/// (key + enabled). Teacher (Platform Owner) only.
class PlatformFeaturesScreen extends StatelessWidget {
  final AuthUser user;

  const PlatformFeaturesScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context) {
    if (user.role != 'teacher') {
      return const Scaffold(
        body: Center(child: Text('هذه الشاشة متاحة للمعلم (مالك المنصة) فقط.')),
      );
    }

    final features = FirebaseFirestore.instance
        .collection('platform_features')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('ميزات المنصة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: features,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل ميزات المنصة.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              const Text(
                'أي تبديل هنا يُطبَّق فوراً على المنصة كلها من قاعدة البيانات، بدون نشر كود جديد.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد ميزات مسجلة بعد.')),
                )
              else
                ...docs.map((doc) => _PlatformFeatureCard(feature: doc)),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: '+ إضافة ميزة جديدة',
                icon: Icons.add_circle_outline,
                variant: AppButtonVariant.outlined,
                onPressed: () => _showAddFeatureDialog(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddFeatureDialog(BuildContext context) async {
    final keyController = TextEditingController();
    final labelController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة ميزة للمنصة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'مفتاح الميزة (feature key)',
                hintText: 'مثال: chat.enabled',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'الاسم المعروض'),
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
      ),
    );

    final key = keyController.text.trim();
    final label = labelController.text.trim();
    keyController.dispose();
    labelController.dispose();

    if (confirmed != true || key.isEmpty || !context.mounted) return;

    try {
      await FirebaseFunctions.instance.httpsCallable('setPlatformFeature').call({
        'featureKey': key,
        'enabled': false,
        if (label.isNotEmpty) 'label': label,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة الميزة (معطّلة افتراضياً).')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'تعذر إضافة الميزة.')),
        );
      }
    }
  }
}

class _PlatformFeatureCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> feature;

  const _PlatformFeatureCard({required this.feature});

  @override
  State<_PlatformFeatureCard> createState() => _PlatformFeatureCardState();
}

class _PlatformFeatureCardState extends State<_PlatformFeatureCard> {
  bool _pending = false;

  Future<void> _toggle(bool value) async {
    setState(() => _pending = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('setPlatformFeature').call({
        'featureKey': widget.feature.id,
        'enabled': value,
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'تعذر تحديث الميزة.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.feature.data();
    final label = (data['label'] ?? widget.feature.id).toString();
    final enabled = data['enabled'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          widget.feature.id,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        trailing: _pending
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : CupertinoSwitch(
                value: enabled,
                activeTrackColor: AppColors.success,
                onChanged: _toggle,
              ),
      ),
    );
  }
}
