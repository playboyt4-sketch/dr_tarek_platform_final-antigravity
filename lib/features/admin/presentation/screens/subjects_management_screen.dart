import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/admin_grades.dart';

/// Subjects management screen: create, edit (name/visibility/order) and
/// soft-delete subjects through Cloud Functions. Changes apply to the
/// student experience immediately from Firestore - no code deploys.
class SubjectsManagementScreen extends StatelessWidget {
  const SubjectsManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subjects = FirebaseFirestore.instance
        .collection('subjects')
        .where('is_deleted', isEqualTo: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المواد')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: subjects,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل المواد.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final orderA = (a.data()['display_order'] as num?)?.toInt() ?? 0;
              final orderB = (b.data()['display_order'] as num?)?.toInt() ?? 0;
              return orderA.compareTo(orderB);
            });
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد مواد بعد.')),
                )
              else
                ...docs.map((doc) => _SubjectCard(subject: doc)),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: '+ إضافة مادة جديدة',
                icon: Icons.add_circle_outline,
                onPressed: () => _showSubjectDialog(context),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _showSubjectDialog(
    BuildContext context, {
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final nameController = TextEditingController(
      text: existing?.data()['title']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: existing?.data()['description']?.toString() ?? '',
    );
    final orderController = TextEditingController(
      text: (existing?.data()['display_order'] as num?)?.toString() ?? '0',
    );
    // FINAL_DECISIONS §13 enabler: every subject carries its own grade tag
    // (canonical grade_one..grade_four) so prior-term grant UIs can list
    // "subjects from grades 1..N-1". Null = untagged legacy subject.
    String? selectedGrade =
        existing == null ? null : existing.data()['grade'] as String?;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'إضافة مادة جديدة' : 'تعديل المادة'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'اسم المادة'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ترتيب العرض'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGrade,
                    decoration: const InputDecoration(
                      labelText: 'الفرقة (تُستخدم لمنح مواد فرق سابقة)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('بدون فرقة'),
                      ),
                      for (final key in kCanonicalGradeKeys)
                        DropdownMenuItem<String>(
                          value: key,
                          child: Text(gradeLabel(key)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedGrade = value),
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
                child: Text(existing == null ? 'إنشاء' : 'حفظ'),
              ),
            ],
          ),
        );
      },
    );

    final name = nameController.text.trim();
    final description = descriptionController.text.trim();
    final order = int.tryParse(orderController.text.trim()) ?? 0;
    nameController.dispose();
    descriptionController.dispose();
    orderController.dispose();

    if (confirmed != true || name.isEmpty || !context.mounted) return;

    try {
      final functions = FirebaseFunctions.instance;
      if (existing == null) {
        await functions.httpsCallable('createSubject').call({
          'name': name,
          'description': description,
          'displayOrder': order,
          'grade': ?selectedGrade,
        });
      } else {
        await functions.httpsCallable('updateSubject').call({
          'subjectId': existing.id,
          'name': name,
          'description': description,
          'displayOrder': order,
          // Explicit key so the callable can also CLEAR the tag (null).
          'grade': selectedGrade,
        });
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing == null ? 'تم إنشاء المادة.' : 'تم حفظ التعديلات.'),
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'فشلت العملية.'))),
        );
      }
    }
  }

  static Future<void> _deleteSubject(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> subject,
  ) async {
    final name = subject.data()['title']?.toString() ?? subject.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('حذف "$name"؟'),
        content: const Text(
          'سيتم حذف المادة حذفاً ناعماً (soft delete) ولن تظهر للطلاب بعد الآن.',
        ),
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
    if (confirmed != true || !context.mounted) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteSubject')
          .call({'subjectId': subject.id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المادة.')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر حذف المادة.'))),
        );
      }
    }
  }
}

class _SubjectCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> subject;

  const _SubjectCard({required this.subject});

  @override
  State<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<_SubjectCard> {
  bool _pendingVisibility = false;

  Future<void> _toggleVisibility(bool value) async {
    setState(() => _pendingVisibility = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('updateSubject').call({
        'subjectId': widget.subject.id,
        'isVisible': value,
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر تحديث الظهور.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingVisibility = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.subject.data();
    final name = (data['title'] ?? data['name'] ?? widget.subject.id).toString();
    final visible = data['is_visible'] == true;
    final order = (data['display_order'] as num?)?.toInt() ?? 0;
    final grade = data['grade'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'ترتيب العرض: $order'
                        '${grade == null ? '' : ' • ${gradeLabel(grade)}'}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => SubjectsManagementScreen._showSubjectDialog(
                    context,
                    existing: widget.subject,
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => SubjectsManagementScreen._deleteSubject(
                    context,
                    widget.subject,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('ظاهرة للطلاب')),
                _pendingVisibility
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : CupertinoSwitch(
                        value: visible,
                        activeTrackColor: AppColors.success,
                        onChanged: _toggleVisibility,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
