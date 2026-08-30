import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_input.dart';
import '../../domain/entities/admin_content_entities.dart' show AdminSection;
import '../providers/admin_content_providers.dart';
import 'admin_archive_screen.dart';
import 'admin_lectures_screen.dart';

/// Section management per Feature 03: list (system + custom) ordered by
/// display_order, create custom, edit title/visibility, drag-to-reorder,
/// delete custom-only. System sections can be hidden but never deleted —
/// enforced in Rules + Repository + here.
class AdminSectionsScreen extends ConsumerWidget {
  final String subjectId;
  final String subjectTitle;

  const AdminSectionsScreen({
    super.key,
    required this.subjectId,
    required this.subjectTitle,
  });

  void _toast(BuildContext context, Object error, String fallback) {
    if (error is Failure) {
      // Part B: the exact ratified Arabic message for the blocked deletion.
      final message = error.code == FailureCode.sectionHasActiveLectures
          ? error.debugDetail ?? fallback
          : mapFunctionErrorCode(
              'permission-denied', error.debugDetail, fallback);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(fallback)));
    }
  }

  /// Runs a mutation and surfaces any Failure as a friendly snackbar.
  Future<void> _mutate(
    BuildContext context,
    Future<void> Function() action,
    String failureFallback,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) _toast(context, e, failureFallback);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(adminSectionsProvider(subjectId));

    return Scaffold(
      appBar: AppBar(
        title: Text('الأقسام — $subjectTitle'),
        actions: [
          // Archive System (Part B): browse + restore soft-deleted content.
          IconButton(
            tooltip: 'الأرشيف',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdminArchiveScreen(
                subjectId: subjectId,
                subjectTitle: subjectTitle,
              ),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
        onPressed: () => _createDialog(context, ref),
      ),
      body: sections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعذر تحميل الأقسام.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.invalidate(adminSectionsProvider(subjectId)),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('لا توجد أقسام بعد.'));
          // Drag-to-reorder; every drop rewrites 1..n display_order in one
          // atomic batch (ReorderSections use case). onReorderItem already
          // adjusts newIndex for the removed item.
          return ReorderableListView.builder(
            itemCount: list.length,
            onReorderItem: (oldIndex, newIndex) {
              final items = [...list];
              final moved = items.removeAt(oldIndex);
              items.insert(newIndex, moved);
              _mutate(
                context,
                () => ref
                    .read(reorderSectionsUseCaseProvider)
                    .execute(items),
                'تعذر إعادة الترتيب.',
              );
            },
            itemBuilder: (_, i) {
              final section = list[i];
              return Card(
                key: ValueKey(section.id),
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    section.isSystemSection
                        ? Icons.star_outline
                        : Icons.edit_note_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(section.title),
                  subtitle: Text(
                    '${section.isSystemSection ? "قسم نظامي" : "قسم مخصص"}'
                    ' • ترتيب ${section.displayOrder}'
                    ' • ${section.isVisible ? "ظاهر" : "مخفي"}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'lectures':
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdminLecturesScreen(
                              subjectId: subjectId,
                              sectionId: section.id,
                              sectionTitle: section.title,
                            ),
                          ));
                        case 'edit':
                          _editDialog(context, ref, section);
                        case 'toggle':
                          _mutate(
                            context,
                            () => ref
                                .read(updateSectionUseCaseProvider)
                                .execute(section,
                                    newTitle: section.title,
                                    newIsVisible: !section.isVisible),
                            'تعذر تغيير إظهار القسم.',
                          );
                        case 'delete':
                          _delete(context, ref, section);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'lectures', child: Text('المحاضرات')),
                      const PopupMenuItem(
                          value: 'edit',
                          child: Text('تعديل العنوان/الإظهار')),
                      const PopupMenuItem(
                          value: 'toggle', child: Text('تبديل الإظهار')),
                      // System sections NEVER get a delete entry — they can
                      // only be hidden (Feature 03).
                      if (!section.isSystemSection)
                        const PopupMenuItem(
                            value: 'delete', child: Text('حذف القسم')),
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

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    bool visible = true;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('قسم جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            AppInput(controller: titleController, hint: 'عنوان القسم'),
            SwitchListTile(
                value: visible,
                onChanged: (v) => setState(() => visible = v),
                title: const Text('ظاهر للطلاب')),
          ]),
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
    if (titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('عنوان القسم مطلوب.')));
      return;
    }
    await _mutate(
      context,
      () => ref.read(createSectionUseCaseProvider).execute(
          subjectId: subjectId,
          title: titleController.text.trim(),
          isVisible: visible),
      'تعذر إنشاء القسم.',
    );
  }

  Future<void> _editDialog(
      BuildContext context, WidgetRef ref, AdminSection section) async {
    final titleController = TextEditingController(text: section.title);
    bool visible = section.isVisible;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(section.isSystemSection
              ? 'تعديل قسم نظامي (العنوان والإظهار فقط)'
              : 'تعديل القسم'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            AppInput(controller: titleController, hint: 'عنوان القسم'),
            SwitchListTile(
                value: visible,
                onChanged: (v) => setState(() => visible = v),
                title: const Text('ظاهر للطلاب')),
          ]),
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
    await _mutate(
      context,
      () => ref.read(updateSectionUseCaseProvider).execute(section,
          newTitle: titleController.text.trim(), newIsVisible: visible),
      'تعذر حفظ التعديلات.',
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, AdminSection section) async {
    // Repository guard also throws for system sections — belt & braces.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القسم'),
        content: Text(
            'سيتم حذف القسم "${section.title}" نهائيًا مع بقاء محاضراته. متابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _mutate(
      context,
      () =>
          ref.read(deleteCustomSectionUseCaseProvider).execute(section),
      'تعذر حذف القسم.',
    );
  }
}
