import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_input.dart';
import '../../../lecture/domain/entities/lecture.dart';
import '../providers/admin_content_providers.dart';
import 'admin_resources_screen.dart';

/// Lecture management per Feature 04: list ordered by display_order with
/// publish status, create (title/description/order/publish date), edit
/// metadata, publish toggle, archive (soft delete per MA §10).
class AdminLecturesScreen extends ConsumerWidget {
  final String subjectId;
  final String sectionId;
  final String sectionTitle;

  const AdminLecturesScreen({
    super.key,
    required this.subjectId,
    required this.sectionId,
    required this.sectionTitle,
  });

  Future<void> _mutate(
    BuildContext context,
    Future<void> Function() action,
    String failureFallback,
  ) async {
    try {
      await action();
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mapFunctionErrorCode(
                'permission-denied', failure.debugDetail, failureFallback))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureFallback)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectures = ref.watch(adminLecturesProvider(sectionId));

    return Scaffold(
      appBar: AppBar(title: Text('المحاضرات — $sectionTitle')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
        onPressed: () => _createDialog(context, ref),
      ),
      body: lectures.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعذر تحميل المحاضرات.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.invalidate(adminLecturesProvider(sectionId)),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('لا توجد محاضرات بعد.'));
          }
          return ReorderableListView.builder(
            itemCount: list.length,
            onReorderItem: (oldIndex, newIndex) {
              final items = [...list];
              items.insert(newIndex, items.removeAt(oldIndex));
              _mutate(
                context,
                () =>
                    ref.read(reorderLecturesUseCaseProvider).execute(items),
                'تعذر إعادة الترتيب.',
              );
            },
            itemBuilder: (_, i) {
              final lecture = list[i];
              final published = lecture.status == LectureStatus.published;
              return Card(
                key: ValueKey(lecture.id),
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    published ? Icons.public : Icons.drafts_outlined,
                    color: published ? Colors.green : AppColors.primary,
                  ),
                  title: Text(lecture.title),
                  subtitle: Text(
                    '${published ? "منشورة" : lecture.status == LectureStatus.archived ? "مؤرشفة" : "مسودة"}'
                    ' • ترتيب ${lecture.displayOrder}'
                    '${lecture.publishDate != null ? " • النشر: ${_dateLabel(lecture.publishDate!)}" : ""}'
                    // FINAL_DECISIONS §11 per-lecture Public Free state.
                    '${lecture.publicFreeEnabled ? " • متاحة للفري العام (${lecture.publicFreePreviewMinutes ?? "افتراضي الباقة"} د)" : ""}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'resources':
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdminResourcesScreen(
                                lectureId: lecture.id,
                                lectureTitle: lecture.title),
                          ));
                        case 'edit':
                          _editDialog(context, ref, lecture);
                        case 'publish':
                          _mutate(
                            context,
                            () => ref
                                .read(setLecturePublishedUseCaseProvider)
                                .execute(
                                    lectureId: lecture.id,
                                    published: !published),
                            'تعذر تغيير حالة النشر.',
                          );
                        case 'archive':
                          _archive(context, ref, lecture.id);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'resources',
                          child: Text('الموارد (فيديو/PDF/روابط)')),
                      const PopupMenuItem(
                          value: 'edit', child: Text('تعديل البيانات')),
                      PopupMenuItem(
                          value: 'publish',
                          child:
                              Text(published ? 'إلغاء النشر' : 'نشر المحاضرة')),
                      const PopupMenuItem(
                          value: 'archive', child: Text('أرشفة')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  /// FINAL_DECISIONS §11: the exact toggle + minutes pair — a green/gray
  /// switch "إتاحة للفري العام" with the numeric minutes field beside it.
  Widget _publicFreeControls({
    required bool enabled,
    required TextEditingController minutes,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      children: [
        Switch(
          value: enabled,
          activeTrackColor: AppColors.success, // green = available
          inactiveTrackColor: Colors.grey, // gray = not available
          onChanged: onToggle,
        ),
        Expanded(
          child: Text(
            'إتاحة للفري العام',
            style: TextStyle(color: enabled ? AppColors.success : Colors.grey),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextField(
            controller: minutes,
            keyboardType: TextInputType.number,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'دقائق مسموحة',
              hintText: 'مثال: 5',
            ),
          ),
        ),
      ],
    );
  }

  int? _parseMinutes(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final publicFreeMinutes = TextEditingController();
    bool publicFreeEnabled = false;
    DateTime? publishDate;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('محاضرة جديدة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppInput(controller: title, hint: 'عنوان المحاضرة'),
              const SizedBox(height: 8),
              AppInput(controller: description, hint: 'الوصف (اختياري)'),
              const SizedBox(height: 8),
              // Publish date controls when the lecture goes live for students;
              // auto-publish flips it once the date passes (Part D).
              Row(children: [
                Expanded(
                  child: Text(publishDate == null
                      ? 'بدون تاريخ نشر (فوري عند النشر)'
                      : 'تاريخ النشر: ${_dateLabel(publishDate!)}'),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: publishDate ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => publishDate = picked);
                  },
                ),
              ]),
              const SizedBox(height: 8),
              // FINAL_DECISIONS §11 per-lecture Public Free access.
              _publicFreeControls(
                enabled: publicFreeEnabled,
                minutes: publicFreeMinutes,
                onToggle: (v) => setState(() => publicFreeEnabled = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (created != true || !context.mounted) return;
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('عنوان المحاضرة مطلوب.')));
      return;
    }
    final minutes = _parseMinutes(publicFreeMinutes);
    if (publicFreeEnabled && minutes != null && minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الدقائق المسموحة يجب أن تكون رقمًا أكبر من صفر.')));
      return;
    }
    await _mutate(
      context,
      () => ref.read(createLectureUseCaseProvider).execute(
            subjectId: subjectId,
            sectionId: sectionId,
            title: title.text.trim(),
            description: description.text.trim(),
            displayOrder: null, // appended after the last lecture
            publishDate: publishDate,
            publicFreeEnabled: publicFreeEnabled,
            publicFreePreviewMinutes:
                publicFreeEnabled ? minutes : null,
          ),
      'تعذر إنشاء المحاضرة.',
    );
  }

  Future<void> _editDialog(
      BuildContext context, WidgetRef ref, Lecture lecture) async {
    final title = TextEditingController(text: lecture.title);
    final description = TextEditingController(text: lecture.description);
    final publicFreeMinutes = TextEditingController(
        text: lecture.publicFreePreviewMinutes?.toString() ?? '');
    bool publicFreeEnabled = lecture.publicFreeEnabled;
    DateTime? publishDate = lecture.publishDate;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('تعديل المحاضرة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppInput(controller: title, hint: 'العنوان'),
              const SizedBox(height: 8),
              AppInput(controller: description, hint: 'الوصف'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(publishDate == null
                      ? 'بدون تاريخ نشر'
                      : 'تاريخ النشر: ${_dateLabel(publishDate!)}'),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: publishDate ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => publishDate = picked);
                  },
                ),
              ]),
              const SizedBox(height: 8),
              // FINAL_DECISIONS §11: green/gray toggle + numeric field.
              _publicFreeControls(
                enabled: publicFreeEnabled,
                minutes: publicFreeMinutes,
                onToggle: (v) => setState(() => publicFreeEnabled = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final minutes = _parseMinutes(publicFreeMinutes);
    if (publicFreeEnabled && minutes != null && minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الدقائق المسموحة يجب أن تكون رقمًا أكبر من صفر.')));
      return;
    }
    await _mutate(
      context,
      () => ref.read(updateLectureMetadataUseCaseProvider).execute(
            lectureId: lecture.id,
            title: title.text.trim(),
            description: description.text.trim(),
            displayOrder: lecture.displayOrder,
            publishDate: publishDate,
            publicFreeEnabled: publicFreeEnabled,
            publicFreePreviewMinutes:
                publicFreeEnabled ? minutes : null,
          ),
      'تعذر حفظ التعديلات.',
    );
  }

  Future<void> _archive(
      BuildContext context, WidgetRef ref, String lectureId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أرشفة المحاضرة'),
        content: const Text(
            'ستُخفى المحاضرة عن الطلاب ويمكن استرجاعها من الأرشيف لاحقًا '
            '(لا يتم الحذف نهائيًا أبدًا).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أرشفة')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _mutate(
        context,
        () => ref.read(archiveLectureUseCaseProvider).execute(lectureId),
        'تعذر أرشفة المحاضرة.',
      );
    }
  }
}
